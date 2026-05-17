// Disassemble small SPU local-store windows from a raw/base-zero import.
// Usage:
//   -postScript DisassembleSpuWindows.java C:\out.txt 0x40 0x25cc 0x451c

import java.io.File;
import java.io.PrintWriter;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSpace;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;

public class DisassembleSpuWindows extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 3) {
            println("Usage: DisassembleSpuWindows.java <out-file> <window-bytes> <address> [address...]");
            return;
        }

        File outFile = new File(args[0]);
        File parent = outFile.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }

        int windowBytes = Integer.decode(args[1]);
        AddressSpace space = currentProgram.getAddressFactory().getDefaultAddressSpace();

        try (PrintWriter out = new PrintWriter(outFile, "UTF-8")) {
            out.println("Program: " + currentProgram.getName());
            out.println("Language: " + currentProgram.getLanguageID());
            out.println("WindowBytes: 0x" + Integer.toHexString(windowBytes));
            out.println();

            for (int i = 2; i < args.length; i++) {
                Address center = space.getAddress(args[i]);
                Address start = subtractClamped(center, windowBytes);
                Address end = center.addNoWrap(windowBytes);

                out.println("==== " + args[i] + " (" + start + ".." + end + ") ====");
                disassembleWindow(start, end);
                dumpInstructions(out, start, end, center);
                out.println();
            }
        }

        println("Wrote " + outFile.getAbsolutePath());
    }

    private Address subtractClamped(Address address, long amount) {
        try {
            return address.subtractNoWrap(amount);
        } catch (Exception e) {
            return address.getAddressSpace().getMinAddress();
        }
    }

    private void disassembleWindow(Address start, Address end) throws Exception {
        clearListing(start, end);
        Address cursor = start;
        while (cursor.compareTo(end) <= 0 && !monitor.isCancelled()) {
            if (getInstructionAt(cursor) == null) {
                disassemble(cursor);
            }
            cursor = cursor.addNoWrap(4);
        }
    }

    private void dumpInstructions(PrintWriter out, Address start, Address end, Address center) {
        InstructionIterator it = currentProgram.getListing().getInstructions(start, true);
        int count = 0;
        while (it.hasNext() && !monitor.isCancelled()) {
            Instruction instruction = it.next();
            Address address = instruction.getAddress();
            if (address.compareTo(end) > 0) {
                break;
            }

            String marker = address.equals(center) ? "=>" : "  ";
            out.print(marker + " " + address + ": " + instruction);

            Address fallThrough = instruction.getFallThrough();
            Address[] flows = instruction.getFlows();
            if (fallThrough != null || flows.length > 0) {
                out.print("    ; flow");
                if (fallThrough != null) {
                    out.print(" fall=" + fallThrough);
                }
                for (Address flow : flows) {
                    out.print(" target=" + flow);
                }
            }

            out.println();
            count++;
        }

        if (count == 0) {
            out.println("  <no instructions decoded>");
        }
    }
}
