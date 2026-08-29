// Find a byte sequence in all initialized memory blocks.
// Usage:
//   -postScript FindBytes.java C:\out.txt 9f72add3

import java.io.File;
import java.io.PrintWriter;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;

public class FindBytes extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 2) {
            println("Usage: FindBytes.java <out-file> <hex-bytes>");
            return;
        }

        byte[] pattern = parseHex(args[1]);
        File outFile = new File(args[0]);
        File parent = outFile.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }

        Memory memory = currentProgram.getMemory();
        try (PrintWriter out = new PrintWriter(outFile, "UTF-8")) {
            out.println("Program: " + currentProgram.getName());
            out.println("Language: " + currentProgram.getLanguageID());
            out.println("Pattern: " + args[1]);
            out.println();

            int matches = 0;
            for (MemoryBlock block : memory.getBlocks()) {
                if (!block.isInitialized()) {
                    continue;
                }

                Address cursor = block.getStart();
                while (cursor != null && cursor.compareTo(block.getEnd()) <= 0
                    && !monitor.isCancelled()) {
                    Address match = memory.findBytes(cursor, block.getEnd(), pattern, null, true, monitor);
                    if (match == null) {
                        break;
                    }

                    matches++;
                    out.println("==== match " + matches + " at " + match
                        + " block=" + block.getName() + " ====");

                    int fromCount = 0;
                    for (Reference reference : currentProgram.getReferenceManager().getReferencesFrom(match)) {
                        out.println("  -> " + reference.getToAddress() + " " + reference.getReferenceType());
                        fromCount++;
                    }
                    if (fromCount == 0) {
                        out.println("  references from: <none>");
                    }

                    int toCount = 0;
                    for (Reference reference : currentProgram.getReferenceManager().getReferencesTo(match)) {
                        out.println("  <- " + reference.getFromAddress() + " " + reference.getReferenceType());
                        toCount++;
                    }
                    if (toCount == 0) {
                        out.println("  references to: <none>");
                    }
                    out.println();

                    try {
                        cursor = match.addNoWrap(1);
                    } catch (Exception exception) {
                        cursor = null;
                    }
                }
            }

            out.println("Matches: " + matches);
        }

        println("Wrote " + outFile.getAbsolutePath());
    }

    private byte[] parseHex(String value) {
        String hex = value.replace("0x", "").replaceAll("[^0-9A-Fa-f]", "");
        if (hex.isEmpty() || (hex.length() & 1) != 0) {
            throw new IllegalArgumentException("The byte sequence must contain full hexadecimal bytes.");
        }

        byte[] bytes = new byte[hex.length() / 2];
        for (int i = 0; i < bytes.length; i++) {
            bytes[i] = (byte) Integer.parseInt(hex.substring(i * 2, i * 2 + 2), 16);
        }
        return bytes;
    }
}
