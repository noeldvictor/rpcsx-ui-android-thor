// Find decoded instructions with a specific mnemonic and scalar immediate.
// Usage:
//   -postScript FindInstructionImmediate.java C:\out.txt 0x10000 0x40e000 li 0x60 0x20

import java.io.File;
import java.io.PrintWriter;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.address.AddressSpace;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;

public class FindInstructionImmediate extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 6) {
            println("Usage: FindInstructionImmediate.java <out-file> <start> <end> <mnemonic> <immediate> <window-bytes>");
            return;
        }

        File outFile = new File(args[0]);
        File parent = outFile.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }

        AddressSpace space = currentProgram.getAddressFactory().getDefaultAddressSpace();
        Address start = space.getAddress(args[1]);
        Address end = space.getAddress(args[2]);
        if (start.compareTo(end) >= 0) {
            println("Range end must be greater than start");
            return;
        }

        String mnemonic = args[3];
        long immediate = Long.decode(args[4]);
        long windowBytes = Long.decode(args[5]);
        AddressSet range = new AddressSet(start, end.subtract(1));

        try (PrintWriter out = new PrintWriter(outFile, "UTF-8")) {
            out.println("Program: " + currentProgram.getName());
            out.println("Language: " + currentProgram.getLanguageID());
            out.println("Range: [" + start + "," + end + ")");
            out.println("Mnemonic: " + mnemonic);
            out.println("Immediate: 0x" + Long.toHexString(immediate));
            out.println();

            InstructionIterator instructions = currentProgram.getListing().getInstructions(range, true);
            int matches = 0;
            while (instructions.hasNext() && !monitor.isCancelled()) {
                Instruction instruction = instructions.next();
                if (!instruction.getMnemonicString().equalsIgnoreCase(mnemonic)
                    || !hasImmediate(instruction, immediate)) {
                    continue;
                }

                matches++;
                Function function = currentProgram.getFunctionManager()
                    .getFunctionContaining(instruction.getAddress());
                out.println("==== match " + matches + " at " + instruction.getAddress()
                    + " function=" + (function == null ? "<none>" : function.getName()) + " ====");
                dumpWindow(out, instruction.getAddress(), windowBytes);
                out.println();
            }

            out.println("Matches: " + matches);
        }

        println("Wrote " + outFile.getAbsolutePath());
    }

    private boolean hasImmediate(Instruction instruction, long immediate) {
        for (int operand = 0; operand < instruction.getNumOperands(); operand++) {
            for (Object object : instruction.getOpObjects(operand)) {
                if (object instanceof Scalar) {
                    Scalar scalar = (Scalar) object;
                    if (scalar.getUnsignedValue() == immediate
                        || scalar.getSignedValue() == immediate) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private void dumpWindow(PrintWriter out, Address center, long windowBytes) {
        Address start = subtractClamped(center, windowBytes);
        Address end = addClamped(center, windowBytes);
        InstructionIterator instructions = currentProgram.getListing().getInstructions(start, true);
        while (instructions.hasNext() && !monitor.isCancelled()) {
            Instruction instruction = instructions.next();
            Address address = instruction.getAddress();
            if (address.compareTo(end) > 0) {
                break;
            }

            out.println((address.equals(center) ? "=> " : "   ")
                + address + ": " + instruction);
        }
    }

    private Address subtractClamped(Address address, long amount) {
        try {
            return address.subtractNoWrap(amount);
        } catch (Exception e) {
            return address.getAddressSpace().getMinAddress();
        }
    }

    private Address addClamped(Address address, long amount) {
        try {
            return address.addNoWrap(amount);
        } catch (Exception e) {
            return address.getAddressSpace().getMaxAddress();
        }
    }
}
