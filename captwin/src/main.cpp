#include "print_job.hpp"
#include "print_server.hpp"
#include "Core/Log.hpp"
#include "UsbBackend/UsbBackend.hpp"
#include "UsbBackend/UsbError.hpp"
#include "libcapt/BasicCaptPrinter.hpp"
#include "libcapt/Protocol/ExtendedStatus.hpp"
#include "UsbBackend/UsbStreambuf.hpp"
#include <filesystem>
#include <iostream>
#include <iomanip>
#include <string>
#include <string_view>

namespace {
void usage() {
    std::cerr
        << "Canon CAPT v1 printer tool for Windows (LBP-1120 / LBP810 / LBP3200 ...)\n\n"
        << "Usage:\n"
        << "  captwin list              List USB CAPT printers\n"
        << "  captwin status            Query printer status (default VID:PID 04a9:262b)\n"
        << "  captwin print <file.pbm>  Print P4 PBM raster at 600 dpi\n"
        << "  captwin testpage          Print bundled test page\n"
        << "  captwin serve             Listen on 127.0.0.1:9100 for Windows print jobs (Ctrl+P)\n\n"
        << "Options (status/print/testpage):\n"
        << "  --vid HEX   USB vendor ID (default 04a9)\n"
        << "  --pid HEX   USB product ID (default 262b)\n"
        << "  -v          Verbose libusb logs\n"
        << "  --port N    For serve (default 9100)\n";
}

void parseOptions(int argc, char* argv[], int start, PrintOptions& opt) {
    for (int i = start; i < argc; ++i) {
        std::string_view arg = argv[i];
        if (arg == "-v") {
            opt.verbose = true;
        } else if (arg == "--vid" && i + 1 < argc) {
            opt.vendorId = static_cast<uint16_t>(std::stoul(argv[++i], nullptr, 16));
        } else if (arg == "--pid" && i + 1 < argc) {
            opt.productId = static_cast<uint16_t>(std::stoul(argv[++i], nullptr, 16));
        }
    }
}

struct NullStopToken {
    bool stop_requested() const noexcept { return false; }
};

int cmdList() {
    UsbBackend backend;
    backend.Init();
    auto printers = backend.GetPrinters();
    if (printers.empty()) {
        std::cout << "No USB printer class devices found.\n";
        return 0;
    }
    for (auto& dev : printers) {
        std::cout << std::hex << std::setfill('0') << std::setw(4) << dev.VendorId()
                  << ':' << std::setw(4) << dev.ProductId() << std::dec;
        if (auto info = dev.GetPrinterInfo()) {
            std::cout << "  " << info->Manufacturer << ' ' << info->Model
                      << "  CMD=" << info->CommandSet << " VER=" << info->CmdVersion;
            if (info->IsCaptPrinter()) {
                std::cout << "  [CAPT]";
            }
        }
        std::cout << '\n';
    }
    return 0;
}

int cmdStatus(const PrintOptions& opt) {
    UsbBackend backend;
    backend.Init();
    for (auto& dev : backend.GetPrinters()) {
        if (dev.VendorId() != opt.vendorId || dev.ProductId() != opt.productId) {
            continue;
        }
        dev.Open();
        UsbStreambuf buf(dev);
        std::iostream stream(&buf);
        Capt::BasicCaptPrinter<NullStopToken> printer(stream);
        auto ex = printer.GetStatus();
        auto pi = printer.GetPrinterInfo();
        dev.Close();

        std::cout << "CAPT printer info: deviceId=" << static_cast<int>(pi.DeviceId)
                  << " type=" << static_cast<int>(pi.Type)
                  << " ver=" << static_cast<int>(pi.VersionMajor) << '.'
                  << static_cast<int>(pi.VersionMinor)
                  << " block=" << pi.BlockSize << " buffers=" << pi.Buffers << "\n";
        std::cout << "Status ready=" << ex.Ready() << " online=" << ex.Online()
                  << " paper=" << static_cast<int>(ex.PaperAvailableBits) << "\n";
        return 0;
    }
    std::cerr << "Printer " << std::hex << opt.vendorId << ':' << opt.productId
              << std::dec << " not found or libusb could not open it.\n";
    return 1;
}

std::filesystem::path testPagePath(char* argv0) {
    const std::filesystem::path exeDir = std::filesystem::path(argv0).parent_path();
    const std::filesystem::path bundled = exeDir / "data" / "example-1.pbm";
    if (std::filesystem::exists(bundled)) {
        return bundled;
    }
    const std::filesystem::path dev = exeDir.parent_path().parent_path()
        / "libcapt" / "examples" / "data" / "example-1.pbm";
    if (std::filesystem::exists(dev)) {
        return dev;
    }
    return bundled;
}
} // namespace

int main(int argc, char* argv[]) {
    if (argc < 2) {
        usage();
        return 1;
    }

    PrintOptions opt;
    std::string_view cmd = argv[1];

    if (cmd == "list") {
        try {
            return cmdList();
        } catch (const UsbError& e) {
            std::cerr << "USB error: " << e.what() << " (" << e.StrErrcode() << ")\n";
            return 1;
        }
    }

    if (cmd == "status") {
        parseOptions(argc, argv, 2, opt);
        try {
            return cmdStatus(opt);
        } catch (const UsbError& e) {
            std::cerr << "USB error: " << e.what() << " (" << e.StrErrcode() << ")\n";
            return 1;
        }
    }

    if (cmd == "print") {
        std::filesystem::path pbm;
        for (int i = 2; i < argc; ++i) {
            std::string_view a = argv[i];
            if (a == "-v") {
                opt.verbose = true;
            } else if (a == "--vid" && i + 1 < argc) {
                opt.vendorId = static_cast<uint16_t>(std::stoul(argv[++i], nullptr, 16));
            } else if (a == "--pid" && i + 1 < argc) {
                opt.productId = static_cast<uint16_t>(std::stoul(argv[++i], nullptr, 16));
            } else if (a.starts_with('-')) {
                std::cerr << "Unknown option: " << a << "\n";
                return 1;
            } else {
                pbm = argv[i];
            }
        }
        if (pbm.empty()) {
            usage();
            return 1;
        }
        if (opt.verbose) {
            Log::SetLogStream(std::cerr);
        }
        try {
            return RunPrintJob(pbm, opt);
        } catch (const UsbError& e) {
            std::cerr << "USB error: " << e.what() << " (" << e.StrErrcode() << ")\n";
            return 1;
        } catch (const std::exception& e) {
            std::cerr << "Error: " << e.what() << "\n";
            return 1;
        }
    }

    if (cmd == "testpage") {
        parseOptions(argc, argv, 2, opt);
        std::filesystem::path pbm = testPagePath(argv[0]);
        if (!std::filesystem::exists(pbm)) {
            std::cerr << "Test PBM not found: " << pbm << "\n";
            return 1;
        }
        if (opt.verbose) {
            Log::SetLogStream(std::cerr);
        }
        std::cerr << "Printing " << pbm << "\n";
        try {
            return RunPrintJob(pbm, opt);
        } catch (const UsbError& e) {
            std::cerr << "USB error: " << e.what() << " (" << e.StrErrcode() << ")\n";
            return 1;
        } catch (const std::exception& e) {
            std::cerr << "Error: " << e.what() << "\n";
            return 1;
        }
    }

    if (cmd == "serve") {
        uint16_t port = 9100;
        for (int i = 2; i < argc; ++i) {
            std::string_view a = argv[i];
            if (a == "-v") {
                opt.verbose = true;
            } else if (a == "--vid" && i + 1 < argc) {
                opt.vendorId = static_cast<uint16_t>(std::stoul(argv[++i], nullptr, 16));
            } else if (a == "--pid" && i + 1 < argc) {
                opt.productId = static_cast<uint16_t>(std::stoul(argv[++i], nullptr, 16));
            } else if (a == "--port" && i + 1 < argc) {
                port = static_cast<uint16_t>(std::stoul(argv[++i]));
            } else {
                std::cerr << "Unknown option: " << a << "\n";
                return 1;
            }
        }
        if (opt.verbose) {
            Log::SetLogStream(std::cerr);
        }
        return RunPrintServer(port, opt);
    }

    usage();
    return 1;
}
