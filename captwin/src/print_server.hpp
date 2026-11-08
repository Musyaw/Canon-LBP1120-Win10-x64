#pragma once
#include "print_job.hpp"
#include <cstdint>
#include <filesystem>
#include <vector>

[[nodiscard]] std::filesystem::path FindGhostscriptExecutable();

[[nodiscard]] std::vector<std::filesystem::path> ConvertPostScriptToPbmPages(
    const std::filesystem::path& gsExe,
    const std::filesystem::path& psFile,
    const std::filesystem::path& workDir,
    unsigned dpi = 600
);

[[nodiscard]] int RunPrintServer(uint16_t port, const PrintOptions& options);
