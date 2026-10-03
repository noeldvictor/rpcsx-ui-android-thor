#pragma once

// CHD (MAME Compressed Hunks of Data) disc images: an ISO compressed with chdman createdvd, or
// with createcd, which stores it as one CD data track.
//
// Ported from ARMSX3 7f5e98815, be0559ab6 and 4138e7607 (feature by jdubbing, ARMSX3 PR #173),
// 2026-10-03. ARMSX3 reads a CHD through its own ISO loader. This tree's ISO loader is
// rpcs3/dev/iso.cpp (iso_dev over a block device), so here a CHD is an fs::file over the
// decompressed image, and everything that reads an .iso through an fs::file reads it unchanged.

#include "util/File.h"
#include "util/types.hpp"

#include <memory>
#include <string>

namespace chd
{
	class image;

	// Whether the file starts with the CHD signature. Reads 8 bytes.
	bool is_chd_file(const std::string& path);

	// The same check on an open file. Also requires a version 5 header, the only version this
	// loader reads. Reads 16 bytes and does not move the file position.
	bool is_chd_file(const fs::file& file);

	// Opens the image, decoding its hunk map. Null when it cannot be read; the log says why.
	std::shared_ptr<image> open(const std::string& path);

	// The same, over a file that is already open (an Android file descriptor, for example).
	// `name` is only used in log lines.
	std::shared_ptr<image> open(fs::file&& file, const std::string& name);

	// A file over the whole decompressed image, with its own position. Any number can be open on
	// one image, from any thread.
	fs::file make_file(std::shared_ptr<image> img);

	// If `file` is a CHD, a file over its decompressed image; if it is not, `file` itself. An
	// empty file when it is a CHD that does not open (the log says why).
	fs::file wrap_if_chd(fs::file&& file, const std::string& name);
}
