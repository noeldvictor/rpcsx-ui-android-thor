// Print saved program-context values for one register at selected addresses.
// Usage:
//   -postScript InspectRegisterContext.java C:\out.txt r2 0x002ed984 0x00313360

import java.io.File;
import java.io.PrintWriter;
import java.math.BigInteger;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;

public class InspectRegisterContext extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 3) {
            println("Usage: InspectRegisterContext.java <out-file> <register> <address> [address...]");
            return;
        }

        File outFile = new File(args[0]);
        File parent = outFile.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }

        Register register = currentProgram.getRegister(args[1]);
        if (register == null) {
            println("Unknown register: " + args[1]);
            return;
        }

        try (PrintWriter out = new PrintWriter(outFile, "UTF-8")) {
            out.println("Program: " + currentProgram.getName());
            out.println("Language: " + currentProgram.getLanguageID());
            out.println("Register: " + register.getName());
            out.println();

            for (int i = 2; i < args.length; i++) {
                Address address = currentProgram.getAddressFactory()
                    .getDefaultAddressSpace()
                    .getAddress(args[i]);
                BigInteger value = currentProgram.getProgramContext()
                    .getValue(register, address, false);
                out.println(address + " = " + (value == null ? "<unknown>" : "0x" + value.toString(16)));
            }
        }

        println("Wrote " + outFile.getAbsolutePath());
    }
}
