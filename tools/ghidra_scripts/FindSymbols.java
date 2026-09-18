// Find symbols whose names contain one or more text patterns.
// Usage:
//   -postScript FindSymbols.java C:\out.txt JoinTaskset ShutdownTaskset

// The search is case-insensitive. The output includes the symbol type and the
// function that contains the symbol address, when one exists.

import java.io.File;
import java.io.PrintWriter;
import java.util.Locale;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

public class FindSymbols extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            println("Usage: FindSymbols.java <out-file> <pattern> [pattern...]");
            return;
        }

        File outFile = new File(args[0]);
        File parent = outFile.getParentFile();
        if (parent != null) {
            parent.mkdirs();
        }

        String[] patterns = new String[args.length - 1];
        for (int i = 1; i < args.length; i++) {
            patterns[i - 1] = args[i].toLowerCase(Locale.ROOT);
        }

        try (PrintWriter out = new PrintWriter(outFile, "UTF-8")) {
            out.println("Program: " + currentProgram.getName());
            out.println("Language: " + currentProgram.getLanguageID());
            out.println();

            SymbolIterator symbols = currentProgram.getSymbolTable().getAllSymbols(true);
            int matches = 0;
            while (symbols.hasNext() && !monitor.isCancelled()) {
                Symbol symbol = symbols.next();
                String name = symbol.getName();
                String lower = name.toLowerCase(Locale.ROOT);

                boolean selected = false;
                for (String pattern : patterns) {
                    if (lower.contains(pattern)) {
                        selected = true;
                        break;
                    }
                }

                if (!selected) {
                    continue;
                }

                matches++;
                Function function = currentProgram.getFunctionManager()
                    .getFunctionContaining(symbol.getAddress());
                out.println(symbol.getAddress()
                    + " type=" + symbol.getSymbolType()
                    + " name=" + name
                    + " function=" + (function == null ? "<none>" : function.getName()));
            }

            out.println();
            out.println("Matches: " + matches);
        }

        println("Wrote " + outFile.getAbsolutePath());
    }
}
