#include "print_server.hpp"
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string_view>
#include <system_error>
#include <vector>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace fs = std::filesystem;

namespace detail {
constexpr unsigned kCaptPageWidth600 = 4960;
constexpr unsigned kCaptPageHeight600 = 7016;

unsigned pbmStorageRowBytes(unsigned width) { return (width + 7) / 8; }

bool readPbmDimensions(std::istream& stream, unsigned& width, unsigned& height) {
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

unsigned captTargetWidth(unsigned width) {
    unsigned w = std::min(width, kCaptPageWidth600);
    if (w % 8 == 0) {
        return w;
    }
    const unsigned padded = ((w + 7) / 8) * 8;
    if (padded <= kCaptPageWidth600) {
        return padded;
    }
    return (w / 8) * 8;
}

void normalizePbmForCapt(const fs::path& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        throw std::runtime_error("Cannot open PBM for normalize: " + path.string());
    }
    unsigned width = 0;
    unsigned height = 0;
    if (!readPbmDimensions(in, width, height)) {
        return;
    }
    const unsigned targetWidth = captTargetWidth(width);
    if (targetWidth == width && width % 8 == 0) {
        return;
    }

    const unsigned srcRowBytes = pbmStorageRowBytes(width);
    const unsigned dstRowBytes = targetWidth / 8;
    std::vector<std::vector<unsigned char>> rows;
    rows.reserve(height);
    std::vector<unsigned char> row(srcRowBytes);
    for (unsigned y = 0; y < height; ++y) {
        in.read(reinterpret_cast<char*>(row.data()), static_cast<std::streamsize>(srcRowBytes));
        if (!in) {
            throw std::runtime_error("PBM: short read while normalizing");
        }
        if (dstRowBytes > srcRowBytes) {
            row.resize(dstRowBytes, 0);
        } else if (dstRowBytes < srcRowBytes) {
            row.resize(dstRowBytes);
        }
        rows.push_back(row);
    }

    const fs::path tmp = path.parent_path() / (path.stem().string() + ".norm.pbm");
    std::ofstream out(tmp, std::ios::binary);
    out << "P4\n" << targetWidth << ' ' << height << '\n';
    for (const auto& r : rows) {
        out.write(reinterpret_cast<const char*>(r.data()), static_cast<std::streamsize>(r.size()));
    }
    out.close();
    fs::remove(path);
    fs::rename(tmp, path);
}

static fs::path searchPath(const char* name) {
    const char* pathEnv = std::getenv("PATH");
    if (pathEnv == nullptr) {
        return {};
    }
    std::string_view path(pathEnv);
    while (!path.empty()) {
        auto sep = path.find(';');
        std::string_view dir = path.substr(0, sep);
        if (!dir.empty()) {
            fs::path candidate = fs::path(std::string(dir)) / name;
            if (fs::exists(candidate)) {
                return candidate;
            }
        }
        if (sep == std::string_view::npos) {
            break;
        }
        path.remove_prefix(sep + 1);
    }
    return {};
}

static int runCommandLine(const std::string& cmdLine) {
    STARTUPINFOA si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    std::vector<char> mutableCmd(cmdLine.begin(), cmdLine.end());
    mutableCmd.push_back('\0');
    if (!CreateProcessA(
            nullptr,
            mutableCmd.data(),
            nullptr,
            nullptr,
            FALSE,
            CREATE_NO_WINDOW,
            nullptr,
            nullptr,
            &si,
            &pi)) {
        throw std::runtime_error("CreateProcess failed, error " + std::to_string(GetLastError()));
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD exitCode = 1;
    GetExitCodeProcess(pi.hProcess, &exitCode);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return static_cast<int>(exitCode);
}

fs::path findGhostscriptExecutable() {
    if (const char* env = std::getenv("CAPTWIN_GS")) {
        fs::path p(env);
        if (fs::exists(p)) {
            return p;
        }
    }
    wchar_t modulePath[MAX_PATH]{};
    if (GetModuleFileNameW(nullptr, modulePath, MAX_PATH) != 0) {
        fs::path bundled = fs::path(modulePath).parent_path() / "gs" / "bin" / "gswin64c.exe";
        if (fs::exists(bundled)) {
            return bundled;
        }
        bundled = fs::path(modulePath).parent_path() / "gs" / "bin" / "gswin32c.exe";
        if (fs::exists(bundled)) {
            return bundled;
        }
    }
    for (const wchar_t* base : {L"C:\\Program Files\\gs", L"C:\\Program Files (x86)\\gs"}) {
        std::error_code ec;
        if (!fs::exists(base, ec)) {
            continue;
        }
        for (const auto& entry : fs::directory_iterator(base, ec)) {
            if (!entry.is_directory()) {
                continue;
            }
            fs::path exe = entry.path() / "bin" / "gswin64c.exe";
            if (fs::exists(exe)) {
                return exe;
            }
            exe = entry.path() / "bin" / "gswin32c.exe";
            if (fs::exists(exe)) {
                return exe;
            }
        }
    }
    for (const char* name : {"gswin64c.exe", "gswin32c.exe", "gs.exe"}) {
        fs::path p = searchPath(name);
        if (!p.empty()) {
            return p;
        }
    }
    return {};
}

std::vector<fs::path> convertPostScriptToPbmPages(
    const fs::path& gsExe,
    const fs::path& psFile,
    const fs::path& workDir,
    unsigned dpi
) {
    const fs::path outPattern = (workDir / "page-%03d.pbm").string();
    std::ostringstream cmd;
    cmd << '"' << gsExe.string() << '"'
        << " -dNOPAUSE -dBATCH -dSAFER -dQUIET"
        << " -sDEVICE=pbmraw -r" << dpi
        << " -g" << kCaptPageWidth600 << 'x' << kCaptPageHeight600
        << " -dFIXEDMEDIA"
        << " -sOutputFile=\"" << outPattern.string() << '"'
        << " \"" << psFile.string() << '"';

    std::cerr << "Ghostscript: " << cmd.str() << '\n';
    const int code = runCommandLine(cmd.str());
    if (code != 0) {
        throw std::runtime_error("Ghostscript failed, exit code " + std::to_string(code));
    }

    std::vector<fs::path> pages;
    for (const auto& entry : fs::directory_iterator(workDir)) {
        if (entry.path().extension() == ".pbm") {
            pages.push_back(entry.path());
        }
    }
    std::sort(pages.begin(), pages.end());
    if (pages.empty()) {
        throw std::runtime_error("Ghostscript produced no PBM files");
    }
    for (const auto& page : pages) {
        normalizePbmForCapt(page);
    }
    return pages;
}
} // namespace detail

fs::path FindGhostscriptExecutable() {
    return detail::findGhostscriptExecutable();
}

std::vector<fs::path> ConvertPostScriptToPbmPages(
    const fs::path& gsExe,
    const fs::path& psFile,
    const fs::path& workDir,
    unsigned dpi
) {
    return detail::convertPostScriptToPbmPages(gsExe, psFile, workDir, dpi);
}
