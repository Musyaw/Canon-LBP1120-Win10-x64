#pragma once
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>

struct PrintOptions {
    uint16_t vendorId = 0x04A9;
    uint16_t productId = 0x262B;
    bool verbose = false;
};

[[nodiscard]] int RunPrintJob(const std::filesystem::path& pbmPath, const PrintOptions& options);
