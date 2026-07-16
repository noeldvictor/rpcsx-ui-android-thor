// Inspect functions and instructions in an end-exclusive address range.
// Usage:
//   -postScript InspectFunctionRange.java C:\out.txt 0x002acbc8 0x002afce0

import java.io.File;
import java.io.PrintWriter;
import java.util.Iterator;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;

public class InspectFunctionRange extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 3) {
            println("Usage: InspectFunctionRange.java <out-file> <start> <end>");
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
        Address end = currentProgram.getAddressFactory()
            .getDefaultAddressSpace()
            .getAddress(args[2]);
        if (start.compareTo(end) >= 0) {
            println("Range end must be greater than start");
            return;
        }
        AddressSet range = new AddressSet(start, end.subtract(1));

        try (PrintWriter out = new PrintWriter(outFile, "UTF-8")) {
            out.println("Program: " + currentProgram.getName());
            out.println("Language: " + currentProgram.getLanguageID());
            out.println("Range: [" + start + "," + end + ")");
            out.println();

            out.println("Functions:");
            Iterator<Function> functions = currentProgram.getFunctionManager()
                .getFunctionsOverlapping(range);
            while (functions.hasNext()) {
                Function function = functions.next();
                out.println("  " + function.getEntryPoint()
                    + " body=" + function.getBody().getMinAddress()
                    + ".." + function.getBody().getMaxAddress()
                    + " name=" + function.getName());
            }
            out.println();

            out.println("Instructions:");
            InstructionIterator instructions = currentProgram.getListing()
                .getInstructions(range, true);
            while (instructions.hasNext()) {
                Instruction instruction = instructions.next();
                out.println("  " + instruction.getAddress() + ": " + instruction);
            }
        }

        println("Wrote " + outFile.getAbsolutePath());
    }
}
