#include "print_job.hpp"
#include "Core/Log.hpp"
#include "UsbBackend/UsbBackend.hpp"
#include "UsbBackend/UsbStreambuf.hpp"
#include "libcapt/BasicCaptPrinter.hpp"
#include "libcapt/Compression/ScoaStreambuf.hpp"
#include "libcapt/Protocol/Enums.hpp"
#include "libcapt/Protocol/ExtendedStatus.hpp"
#include "libcapt/Protocol/PageParams.hpp"
#include "libcapt/Protocol/ReprintStatus.hpp"
#include "libcapt/Utility/BufferedPage.hpp"
#include <atomic>
#include <cassert>
#include <chrono>
#include <cctype>
#include <csignal>
#include <fstream>
#include <iostream>
#include <optional>
#include <thread>
#include <utility>

using namespace Capt;
using namespace std::literals::chrono_literals;

namespace {
class StopSource {
    std::atomic<bool> stopReq{false};
public:
    bool stop_requested() const noexcept { return stopReq.load(); }
    void request_stop() noexcept { stopReq.store(true); }
};

StopSource g_stop;

class JobStopToken {
    StopSource* src = nullptr;
public:
    JobStopToken() = default;
    explicit JobStopToken(StopSource& s) noexcept : src(&s) {}
    bool stop_requested() const noexcept { return src != nullptr && src->stop_requested(); }
};

bool readPbmHeader(std::istream& stream, unsigned& width, unsigned& height) {
    char buffer[3];
    stream.read(buffer, sizeof(buffer));
    if (stream.eof()) {
        return false;
    }
    if (buffer[0] != 'P' || buffer[1] != '4' || !std::isspace(static_cast<unsigned char>(buffer[2]))) {
        throw std::runtime_error("PBM: invalid magic (expected P4)");
    }
    while (stream.peek() == '#') {
        while (stream.get() != '\n') {
            if (stream.eof()) {
                throw std::runtime_error("PBM: unexpected EOF in comment");
            }
        }
    }
    if (!(stream >> width)) {
        throw std::runtime_error("PBM: failed to read width");
    }
    if (!std::isspace(static_cast<unsigned char>(stream.get()))) {
        throw std::runtime_error("PBM: unexpected char after width");
    }
    if (!(stream >> height)) {
        throw std::runtime_error("PBM: failed to read height");
    }
    while (!std::isspace(static_cast<unsigned char>(stream.get())) && stream.good()) {
    }
    if (stream.eof()) {
        throw std::runtime_error("PBM: unexpected EOF before raster");
    }
    return true;
}

class PbmPageProvider {
    std::istream& pbmStream;
public:
    explicit PbmPageProvider(std::istream& s) : pbmStream(s) {}

    std::optional<PageParams> ReadHeader() {
        unsigned width;
        unsigned lines;
        if (!readPbmHeader(this->pbmStream, width, lines)) {
            return std::nullopt;
        }
        if (width % 8 != 0) {
            throw std::runtime_error("PBM width must be a multiple of 8");
        }
        return PageParams{
            .PaperSize = 0x09,
            .TonerDensity = 0x3f,
            .Mode = 0,
            .Resolution = ResolutionIdx::RES_600,
            .SmoothEnable = true,
            .TonerSaving = false,
            .MarginLeft = 1,
            .MarginTop = 1,
            .ImageLineSize = static_cast<uint16_t>(width / 8),
            .ImageLines = static_cast<uint16_t>(lines),
            .PaperWidth = 4960,
            .PaperHeight = 7014,
        };
    }
};

template<Capt::StopToken Token>
ExtendedStatus waitReady(Token stopToken, BasicCaptPrinter<Token>& printer) {
    ExtendedStatus status = printer.GetStatus();
    while (!status.Ready() && !stopToken.stop_requested()) {
        if (status.ClearErrorNeeded()) {
            printer.ClearError(&status);
        } else if ((status.Engine & EngineReadyStatus::NO_PRINT_PAPER) != 0) {
            std::cerr << "Waiting for paper...\n";
        } else if ((status.Engine & EngineReadyStatus::SERVICE_CALL) != 0) {
            throw std::runtime_error("Printer SERVICE_CALL — check hardware");
        } else {
            std::cerr << "Waiting for printer ready...\n";
        }
        std::this_thread::sleep_for(1s);
        status = printer.GetStatus();
    }
    return status;
}

template<Capt::StopToken Token>
void prepareBeforePrint(Token stopToken, BasicCaptPrinter<Token>& printer, unsigned page) {
    while (true) {
        ExtendedStatus status = waitReady(stopToken, printer);
        if (stopToken.stop_requested()) {
            return;
        }
        assert(status.Ready());
        if (!status.Online() || status.Start != page) {
            if (!printer.GoOnline(page)) {
                std::cerr << "GoOnline failed, retrying...\n";
                std::this_thread::sleep_for(1s);
                continue;
            }
        }
        break;
    }
}

template<Capt::StopToken Token>
bool writePage(Token stopToken, BasicCaptPrinter<Token>& printer, Utility::BufferedPage& page, Utility::BufferedPage* prev) {
    ReprintStatus reprint = ReprintStatus::None;
    while (!stopToken.stop_requested()) {
        Utility::BufferedPage& p = (prev && reprint == ReprintStatus::Prev) ? *prev : page;
        p.pubseekpos(0);
        prepareBeforePrint(stopToken, printer, p.PageNumber);
        if (stopToken.stop_requested()) {
            return true;
        }
        if (reprint != ReprintStatus::None) {
            std::cerr << "Retry page " << p.PageNumber << "...\n";
        } else {
            std::cerr << "Sending page " << p.PageNumber << "...\n";
        }
        if (printer.WriteVideoData(p.Params, p)) {
            if (prev && reprint == ReprintStatus::Prev) {
                reprint = ReprintStatus::None;
                continue;
            }
            break;
        }
        auto status = printer.WaitPrintEnd(stopToken);
        if (!status) {
            return true;
        }
        if (status->VideoDataError()) {
            return false;
        }
        reprint = status->GetReprintStatus();
        std::this_thread::sleep_for(1s);
    }
    return true;
}

template<Capt::StopToken Token>
bool waitLastPage(Token stopToken, BasicCaptPrinter<Token>& printer, Utility::BufferedPage& page) {
    while (!stopToken.stop_requested()) {
        std::this_thread::sleep_for(1s);
        auto status = printer.WaitPrintEnd(stopToken);
        if (!status) {
            return true;
        }
        if (status->VideoDataError()) {
            return false;
        }
        if (status->GetReprintStatus() == ReprintStatus::None) {
            break;
        }
        if (!writePage(stopToken, printer, page, nullptr)) {
            return false;
        }
    }
    return true;
}

int printViaUsb(UsbPrinter& device, std::istream& pbmStream) {
    device.Open();
    UsbStreambuf usbBuf(device);
    std::iostream printerStream(&usbBuf);

    JobStopToken stopToken(g_stop);
    BasicCaptPrinter<JobStopToken> printer(printerStream);

    printer.ReserveUnit();
    printer.ClearError();

    PbmPageProvider prov(pbmStream);
    unsigned page = 0;
    Utility::BufferedPage prevPage;
    while (!stopToken.stop_requested()) {
        auto params = prov.ReadHeader();
        if (!params) {
            break;
        }
        Compression::ScoaStreambuf ss(*pbmStream.rdbuf(), params->ImageLineSize, params->ImageLines);
        Utility::BufferedPage currPage(page, *params, &ss);

        if (!writePage(stopToken, printer, currPage, page == 0 ? nullptr : &prevPage)) {
            device.Close();
            return 1;
        }
        prevPage = std::move(currPage);
        page++;
    }

    if (page != 0 && !waitLastPage(stopToken, printer, prevPage)) {
        device.Close();
        return 1;
    }

    printer.GoOffline();
    printer.ReleaseUnit();
    device.Close();
    return 0;
}
} // namespace

int RunPrintJob(const std::filesystem::path& pbmPath, const PrintOptions& options) {
    std::signal(SIGINT, +[](int) {
        std::cerr << "Interrupted\n";
        g_stop.request_stop();
    });

    std::ifstream pbmStream(pbmPath, std::ios::binary);
    if (!pbmStream.is_open()) {
        std::cerr << "Cannot open PBM: " << pbmPath << "\n";
        return 1;
    }

    UsbBackend backend;
    backend.Init();
    auto printers = backend.GetPrinters();

    for (auto& dev : printers) {
        if (dev.VendorId() != options.vendorId || dev.ProductId() != options.productId) {
            continue;
        }
        auto info = dev.GetPrinterInfo();
        if (info && options.verbose) {
            std::cerr << "Device: " << info->Manufacturer << ' ' << info->Model
                      << " CAPT v" << info->CmdVersion << "\n";
        }
        try {
            return printViaUsb(dev, pbmStream);
        } catch (const std::exception& ex) {
            std::cerr << "Print failed: " << ex.what() << "\n";
            return 1;
        }
    }

    std::cerr << "Printer not found (USB " << std::hex << options.vendorId << ':'
              << options.productId << std::dec << ").\n";
    std::cerr << "If libusb cannot open the device, install WinUSB for the printer interface via Zadig "
                 "(https://zadig.akeo.ie/) while the generic usbprint driver is active.\n";
    return 1;
}
