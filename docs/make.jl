using Documenter, CodingTheory

# root = "../",
# 	source = "src",
# 	build = "build",
Documenter.makedocs(
	clean = true,
	doctest = false,
	modules = Module[CodingTheory],
	repo = "",
	highlightsig = true,
	sitename = "Coding Theory Documentation",
	expandfirst = [],
    pages = ["Table Of Contents" => "index.md",
		     "Linear Codes" => "linearcode.md",
		     "Cyclic Codes" => "cycliccode.md",
		     "Reed-Muller Codes" => "ReedMuller.md",
		     "Miscellaneous Known Codes" => "miscknowncodes.md",
			 "LDPC Codes" => "LDPC.md",
		     "Stabilizer Codes" => "quantumcode.md",
		     "Miscellaneous Known Stabilizer Codes" => "miscknownquantumcodes.md",
			 "Hypergraph Product Codes" => "hypergraphproduct.md",
		     "Trellises" => "trellis.md",
		     "Weight Enumerators, Distributions, And Minimum Distances" => "weight_dist.md",
		     "Utilies" => "utils.md",
             "Index" => "theindex.md"]
)

deploydocs(repo = "github.com/esabo/CodingTheory.git")
