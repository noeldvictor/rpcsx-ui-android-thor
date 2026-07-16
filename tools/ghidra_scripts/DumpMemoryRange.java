// Dump a byte range from the currently opened Ghidra program.
// Usage:
//   -postScript DumpMemoryRange.java C:\out.txt 0x00469fa8 0x198

import java.io.File;
import java.io.PrintWriter;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;

public class DumpMemoryRange extends GhidraScript {
    private static final int BYTES_PER_ROW = 16;

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 3) {
            println("Usage: DumpMemoryRange.java <out-file> <start> <length>");
            return;
        }

        File outFile = new File(args[0]);
        File parent = outFile.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }

        Address start = currentProgram.getAddressFactory()
            .getDefaultAddressSpace()
            .getAddress(args[1]);
        long length = Long.decode(args[2]);
        if (length <= 0 || length > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("Length must be in 1..0x7fffffff");
        }

        byte[] bytes = new byte[(int) length];
        Memory memory = currentProgram.getMemory();
        int read = memory.getBytes(start, bytes);
        if (read != bytes.length) {
            throw new IllegalStateException(
                "Expected " + bytes.length + " bytes at " + start + ", read " + read);
        }

        try (PrintWriter out = new PrintWriter(outFile, "UTF-8")) {
            out.println("Program: " + currentProgram.getName());
            out.println("Language: " + currentProgram.getLanguageID());
            out.println("Range: [" + start + "," + start.add(length) + ")");
            out.println("Byte order: " + (currentProgram.getLanguage().isBigEndian() ? "big" : "little"));
            out.println();

            for (int offset = 0; offset < bytes.length; offset += BYTES_PER_ROW) {
                int rowLength = Math.min(BYTES_PER_ROW, bytes.length - offset);
                out.printf("%s:", start.add(offset));
                for (int i = 0; i < rowLength; i++) {
                    out.printf(" %02x", bytes[offset + i] & 0xff);
                }
                out.println();
            }

            out.println();
            out.println("Big-endian u32 words:");
            for (int offset = 0; offset + 4 <= bytes.length; offset += 4) {
                long value = ((long) (bytes[offset] & 0xff) << 24)
                    | ((long) (bytes[offset + 1] & 0xff) << 16)
                    | ((long) (bytes[offset + 2] & 0xff) << 8)
                    | (long) (bytes[offset + 3] & 0xff);
                out.printf("  %s +0x%x: 0x%08x signed=%d%n",
                    start.add(offset), offset, value, (int) value);
            }
        }

        println("Wrote " + outFile.getAbsolutePath());
    }
}
