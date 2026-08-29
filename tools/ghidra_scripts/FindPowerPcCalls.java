// Find direct PowerPC calls to one or more target addresses.
// Usage:
//   -postScript FindPowerPcCalls.java C:\out.txt 0x102b00

import java.io.File;
import java.io.PrintWriter;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressRange;
import ghidra.program.model.address.AddressRangeIterator;
import ghidra.program.model.address.AddressSetView;
import ghidra.program.model.address.AddressSpace;
import ghidra.program.model.mem.Memory;

public class FindPowerPcCalls extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            println("Usage: FindPowerPcCalls.java <out-file> <target> [target...]");
            return;
        }

        File outFile = new File(args[0]);
        File parent = outFile.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }

        AddressSpace space = currentProgram.getAddressFactory().getDefaultAddressSpace();
        long[] targets = new long[args.length - 1];
        for (int i = 1; i < args.length; i++) {
            targets[i - 1] = space.getAddress(args[i]).getOffset();
        }

        Memory memory = currentProgram.getMemory();
        AddressSetView initialized = memory.getAllInitializedAddressSet();

        try (PrintWriter out = new PrintWriter(outFile, "UTF-8")) {
            out.println("Program: " + currentProgram.getName());
            out.println("Language: " + currentProgram.getLanguageID());
            for (long target : targets) {
                out.println("Target: " + space.getAddress(target));
            }
            out.println();

            int matchCount = 0;
            AddressRangeIterator ranges = initialized.getAddressRanges();
            while (ranges.hasNext() && !monitor.isCancelled()) {
                AddressRange range = ranges.next();
                long start = alignUp(range.getMinAddress().getOffset(), 4);
                long end = range.getMaxAddress().getOffset();

                for (long offset = start; offset + 3 <= end; offset += 4) {
                    if ((offset & 0xfffffL) == 0) {
                        monitor.checkCancelled();
                    }

                    Address address = space.getAddress(offset);
                    byte[] bytes = new byte[4];
                    if (memory.getBytes(address, bytes) != 4) {
                        continue;
                    }

                    int word = ((bytes[0] & 0xff) << 24)
                        | ((bytes[1] & 0xff) << 16)
                        | ((bytes[2] & 0xff) << 8)
                        | (bytes[3] & 0xff);
                    if ((word & 0xfc000003) != 0x48000001) {
                        continue;
                    }

                    long displacement = word & 0x03fffffcL;
                    if ((displacement & 0x02000000L) != 0) {
                        displacement -= 0x04000000L;
                    }
                    long target = offset + displacement;

                    for (long requestedTarget : targets) {
                        if (target == requestedTarget) {
                            out.printf("%s: 0x%08x -> %s%n", address, word, space.getAddress(target));
                            matchCount++;
                        }
                    }
                }
            }

            out.println();
            out.println("Matches: " + matchCount);
        }

        println("Wrote " + outFile.getAbsolutePath());
    }

    private long alignUp(long value, long alignment) {
        return (value + alignment - 1) & -alignment;
    }
}
