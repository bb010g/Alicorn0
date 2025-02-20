### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# ╔═╡ b818d46b-d26d-4e99-a16d-05931474b0fb
begin
	const is_pluto_notebook =
		isdefined(@__MODULE__, Symbol("#___this_pluto_module_name"))
	const enable_benchmark = false
	const enable_profile = false
	const enable_dev_analysis = true
	const enable_dev_analysis_dump = true

	import AbstractPlutoDingetjes
	import BenchmarkTools: @benchmark, @benchmarkable, @bprofile, BenchmarkTools
	import HypertextLiteral: @htl
	import JET: @report_call, @report_opt, JET
	import PlutoUI: PlutoUI
	import PrecompileTools: @compile_workload, @setup_workload, PrecompileTools
	import ProfileCanvas: ProfileCanvas

	(; enable_benchmark, enable_profile, enable_dev_analysis, enable_dev_analysis_dump)
end

# ╔═╡ a92297ee-6754-4ece-ba7d-9aa1fb30365c
if is_pluto_notebook
	PlutoUI.HTML("""
<!-- the wrapper span -->
<div><button id="my-restart-notebook" href="#">Restart notebook</button><script>
	const div = currentScript.parentElement;
	const button = div.querySelector(`button#my-restart-notebook`);
	const cell = div.closest(`pluto-cell`);
	console.log(button);
	button.onclick = function() { my_restart_notebook(); };
	function my_restart_notebook() {
		console.log("Restarting Notebook");
		cell._internal_pluto_actions.send("restart_process", {}, {
			notebook_id: editor_state.notebook.notebook_id
		});
	}
</script></div>
	""")
end

# ╔═╡ 065ccb13-c395-45d9-92e6-2fafd9f21520
begin
	@kwdef struct NotebookSection{Id<:AbstractString}
		id::Id
		default::Bool = false
	end
	NotebookSection{Id}(id::Id) where {Id} = NotebookSection{Id}(; id)
	NotebookSection(id::Id) where {Id} = NotebookSection{Id}(id)

	function Base.show(io::IO, m::MIME"text/html", section::NotebookSection)
		section_start_class = "section_start_$(section.id)"
		section_hide_id = "pluto-cell-section_hide_$(section.id)"
		section_end_class = "section_end_$(section.id)"
		Base.show(io, @htl("""<style>
pluto-cell.$(section_start_class):has(input[type="checkbox"]#$(section_hide_id):checked) ~ pluto-cell:has(~ pluto-cell.$(section_end_class)) {
	display: none;
}
</style>
<script>
const cell = currentScript.closest("pluto-cell");
const section_start_class = $(section_start_class);
const set_class = function () {
	cell.classList.toggle(section_start_class, true)
};
set_class();
const observer = new MutationObserver(set_class);
observer.observe(cell, {
	subtree: false,
	attributeFilter: ["class"],
});
invalidation.then(() => {
	observer.disconnect()
	cell.classList.toggle(section_start_class, false)
});
</script>
<label for=$(section_hide_id)>Hide section $("“")$(section.id)$("”"):</label> <input $((type="checkbox", id=section_hide_id, checked=section.default))>"""))
	end
	
	"""The end of a collapsible notebook section."""
	@kwdef struct NotebookEndSection{Id<:AbstractString}
		id::Id
	end

	function Base.show(io::IO, m::MIME"text/html", section::NotebookEndSection)
		section_end_class = "section_end_$(section.id)"
		Base.show(io, @htl("""
<script>
const cell = currentScript.closest("pluto-cell");
const section_end_class = $section_end_class;
const set_class = function () {
	cell.classList.toggle(section_end_class, true)
};
set_class();
const observer = new MutationObserver(set_class);
observer.observe(cell, {
	subtree: false,
	attributeFilter: ["class"],
});
invalidation.then(() => {
	observer.disconnect()
	cell.classList.toggle(section_end_class, false)
});
</script>"""))
	end

	@doc """
	    NotebookSection(id, default=false)

	A collapsible notebook section. Closed with a [`NotebookEndSection`](@ref).
	"""
	NotebookSection
end

# ╔═╡ 2633e081-eb6f-4678-a17c-b5f6d2e92812
import DataStructures: Accumulator, dec!, inc!

# ╔═╡ c02f8f2a-3669-4663-ba92-4ac307e5f456
import IterTools

# ╔═╡ d7ecd0d5-0073-456c-9d1b-48840272120a
import OrderedCollections: OrderedDict, OrderedSet

# ╔═╡ 4faef874-6865-4f25-a6df-35ea0118d3d0
import PlutoTest: @test

# ╔═╡ e27594f1-a61b-4660-b315-be91ea52ccbd
md"""# `runtest.lua`

Should probably be broken up in some more reusable components.
"""

# ╔═╡ d5ac852e-f0e9-49b2-8510-0a969289f7a9
md"""## Module (tree) execution

Pre-actual modules.
"""

# ╔═╡ 7c7bf62e-874d-472a-bc04-b11792594f66
md"""### Type definitions"""

# ╔═╡ f5da097a-e629-4395-8f66-bfe9bf0da3df
begin
	@kwdef struct ExecuterModuleConfig
		# path::Path
		# failure_point::ModuleFailurePoint
		including::Vector{String}
		deduplicate_inclusions::Bool = true
	end
	ExecuterModuleConfig(including) = ExecuterModuleConfig(including, true)
	ExecuterModuleConfig(including::AbstractVector{Pair{String, ExecuterModuleConfig}}, args...) =
		ExecuterModuleConfig(map(pair -> pair.first, including), args...)
	@doc """
		A stripped back version of what's in the Lua.
	"""	ExecuterModuleConfig
end

# ╔═╡ 14bd1588-e550-44f9-ae35-470d93a805db
@kwdef struct ExecuterConfig
	modules::Dict{String, ExecuterModuleConfig}
	modules_to_load::Vector{String}
end

# ╔═╡ 1f8630a1-8a03-40db-bd8f-96c33e2b8aea
md"""### Sample data"""

# ╔═╡ 0c1d47a7-5e6f-4928-ba05-0782d77b99ae
NotebookSection("sample", true)

# ╔═╡ e7b57e0b-896a-4b96-a69a-6e75e6e9d0ca
const sample_prelude = "prelude" => ExecuterModuleConfig([])

# ╔═╡ dc52a346-7e6e-4891-a42d-a2c760e33af4
const sample_glsl_prelude = "glsl-prelude" => ExecuterModuleConfig([sample_prelude])

# ╔═╡ 53c8e07a-ba00-443a-b627-304dd97f3389
const sample_wgpu_prelude = "wgpu-prelude" => ExecuterModuleConfig([sample_prelude])

# ╔═╡ f61ff882-2760-4bb3-82e8-c3e875778498
const sample_test_arith = "tests.arith" => ExecuterModuleConfig([sample_prelude])

# ╔═╡ 9aff452c-7119-4d22-a009-1ab5d55e9ab8
const sample_basic_tests = (;
	arith = sample_test_arith,
)

# ╔═╡ 7d789b92-c028-46c7-a1f0-64b5890382be
executer_config_basic_simple = ExecuterConfig(
	modules=Dict(sample_prelude, sample_basic_tests...),
	modules_to_load=[sample_basic_tests.arith.first]
)

# ╔═╡ e17d1e30-8808-42db-a008-e0274fe51b5d
executer_config_basic = ExecuterConfig(
	modules=Dict(sample_prelude, sample_basic_tests...),
	modules_to_load=[p.first for p in values(sample_basic_tests)]
)

# ╔═╡ d1aef33c-f78b-4088-93bd-8a34962e15bf
"""Includes both `prelude` & `glsl-prelude`."""
const sample_glsl_frag = "tests.glsl-frag" => ExecuterModuleConfig([sample_prelude, sample_glsl_prelude])

# ╔═╡ 69ff6ed6-639f-460a-a006-a997d09d4853
"""Includes only `glsl-prelude`."""
const sample_glsl_vert = "tests.glsl-vert" => ExecuterModuleConfig([sample_glsl_prelude])

# ╔═╡ 8241948a-a280-4b0a-bde2-3783cd4af369
const sample_glsl_tests = (; frag = sample_glsl_frag, vert = sample_glsl_vert)

# ╔═╡ 4ed223ba-7f1f-4def-bbd2-ba63eb0e65de
executer_config_glsl = ExecuterConfig(
	modules=Dict(sample_prelude, sample_glsl_prelude, sample_glsl_tests...),
	modules_to_load=[p.first for p in values(sample_glsl_tests)]
)

# ╔═╡ 05793160-6ad3-4a40-b6dd-7f89ff877fc7
const sample_wgpu_frag = "tests.wgpu-frag" => ExecuterModuleConfig([sample_prelude, sample_wgpu_prelude])

# ╔═╡ 3d0ad692-f004-4071-b797-6df5df8df996
const sample_wgpu_vert = "tests.wgpu-vert" => ExecuterModuleConfig([sample_wgpu_prelude])

# ╔═╡ 7ebf4e23-9950-4131-bb0b-e9783d0cf9ed
const sample_wgpu_tests = (; frag = sample_wgpu_frag, vert = sample_wgpu_vert)

# ╔═╡ c7a45c69-21e0-4115-8ff6-f305ecfc5b2e
executer_config_wgpu = ExecuterConfig(
	modules=Dict(sample_prelude, sample_wgpu_prelude, sample_wgpu_tests...),
	modules_to_load=[p.first for p in values(sample_wgpu_tests)]
)

# ╔═╡ 2c8395c4-eedf-4e18-b649-8cf11773a008
executer_config_graphics = ExecuterConfig(
	modules=merge(executer_config_glsl.modules, executer_config_wgpu.modules),
	modules_to_load=union(executer_config_glsl.modules_to_load, executer_config_wgpu.modules_to_load)
)

# ╔═╡ f96385f3-4480-4464-97cb-0f0c692ba106
begin
	const sample_weird_upper_a = "weird.upper-a" => ExecuterModuleConfig([sample_prelude])
	const sample_weird_upper_b = "weird.upper-b" => ExecuterModuleConfig([sample_prelude])
	const sample_weird_lower_a = "weird.lower-a" => ExecuterModuleConfig([sample_weird_upper_a, sample_weird_upper_b])
	const sample_weird_lower_b = "weird.lower-b" => ExecuterModuleConfig([sample_weird_upper_b, sample_weird_upper_a])
	const sample_weird_a = (; sample_weird_upper_a, sample_weird_upper_b, sample_weird_lower_a, sample_weird_lower_b)
end

# ╔═╡ 3cae07f7-ca03-4d97-a4f8-1c647f07333b
begin
	const sample_weird_bottom_a = "weird.bottom-a" => ExecuterModuleConfig([sample_weird_lower_a, sample_weird_lower_b])
	const sample_weird_b = (; sample_weird_a..., sample_weird_bottom_a)
end

# ╔═╡ 439437d8-7e17-4b76-97b5-c373d7db4d4c
begin
	const sample_weird_bottom_b = "weird.bottom-b" => ExecuterModuleConfig([sample_weird_lower_b, sample_weird_lower_a])
	const sample_weird_c = (; sample_weird_a..., sample_weird_bottom_b)
end

# ╔═╡ 4b837942-d0fb-4327-8de7-e1f32ee03722
NotebookEndSection("sample")

# ╔═╡ 7319c765-6466-4499-86df-9c586ec58ca3
md"""### Implementation
"""

# ╔═╡ 631efdc5-5940-4e8a-9c16-342dc66e9ce4
function unique_if(itr, pred)
	T = Base.eltype(itr)
	seen = Set{T}()
	(x for x in itr if !in(x, seen) && (if pred(x) push!(seen, x) end; true))
end

# ╔═╡ bba836c3-7545-40b5-8406-e465e151fcc0
if enable_dev_analysis @code_warntype debuginfo=:source analyze_module_configs(executer_config_basic_simple) end

# ╔═╡ 01e3d956-3d28-464f-b74b-1d109ef141d5
function report_module_configs_analysis(modules::Dict{String, ExecuterModuleConfig})
	analysis = analyze_module_configs(modules)
	(; modules, analysis...)
end

# ╔═╡ 245ab575-a43e-4d34-9e1d-a6286812c2a7
begin
	struct RoseTree{T}
		node::T
		forest::Vector{RoseTree{T}}
	end
	RoseTree(node::T) where {T} = RoseTree{T}(node)
	function RoseTree{T}(node::T)::RoseTree{T} where {T}
		RoseTree{T}(node, Vector{RoseTree{T}}(undef, 0))
	end
	@doc """
		RoseTree{T}(node::T)
		RoseTree{T}(node::T, forest::Vector{RoseTree{T}})

	A simple rose tree.
	""" RoseTree
end

# ╔═╡ a3d5d045-4ae1-4993-b3c7-7afa81da83ee
Base.get(tree::RoseTree, key, default) = Base.get(tree.forest, key, default)

# ╔═╡ 23acf665-9b8f-481f-acc8-b2f6af1409c8
begin
	function PlutoRunner.tree_data(@nospecialize(x::ExecuterModuleConfig), context::PlutoRunner.Context)
		if Base.show_circular(context, x)
			return PlutoRunner.circular(x)
		else
			depth = get(context, :tree_viewer_depth, 0)
			recur_io_same_depth = PlutoRunner.IOContext(context,
				Pair{Symbol,Any}(:SHOWN_SET, x),
				Pair{Symbol,Any}(:typeinfo, Any),
				Pair{Symbol,Any}(:tree_viewer_depth, depth),
			)
			recur_io = PlutoRunner.IOContext(context,
				Pair{Symbol,Any}(:SHOWN_SET, x),
				Pair{Symbol,Any}(:typeinfo, Any),
				Pair{Symbol,Any}(:tree_viewer_depth, depth + 1),
			)
	
			t = typeof(x)
			nf = nfields(x)
			nb = sizeof(x)
	
			elements = Any[
				let
					f = fieldname(t, i)
					if !isdefined(x, f)
						Base.undef_ref_str
						f, PlutoRunner.format_output_default(PlutoRunner.Text(Base.undef_ref_str), recur_io)
					else
						f, PlutoRunner.format_output_default(getfield(x, i), if (f == :including) recur_io_same_depth else recur_io end)
					end
				end
				for i in 1:nf
			]
	
			Dict{Symbol,Any}(
				:prefix => repr(t; context),
				:prefix_short => string(PlutoRunner.trynameof(t)),
				:objectid => PlutoRunner.objectid2str(x),
				:type => :struct,
				:elements => elements,
			)
		end
	end
	md"""
	[`PlutoRunner.tree_data`](@ref) is overriden for [`ExecuterModuleConfig`](@ref) to increase the depth for `including`, but that might break in the future.
	"""
end

# ╔═╡ 4759265b-a970-4623-8b7b-e3357159ae58
# ╠═╡ disabled = true
#=╠═╡
begin
	function PlutoRunner.tree_data(@nospecialize(x::RoseTree), context::PlutoRunner.Context)
		if Base.show_circular(context, x)
			return PlutoRunner.circular(x)
		else
			depth = get(context, :tree_viewer_depth, 0)
			recur_io = PlutoRunner.IOContext(context,
				Pair{Symbol,Any}(:SHOWN_SET, x),
				Pair{Symbol,Any}(:typeinfo, Any),
				Pair{Symbol,Any}(:tree_viewer_depth, depth),
			)
	
			t = typeof(x)
	
			Dict{Symbol,Any}(
				:prefix => repr(t; context),
				:prefix_short => string(PlutoRunner.trynameof(t)),
				:objectid => PlutoRunner.objectid2str(x),
				:type => :struct,
				:elements => Any[
					(:node, PlutoRunner.format_output_default(x.node, recur_io)),
					(:forest, PlutoRunner.format_output_default(x.forest, recur_io)),
				],
			)
		end
	end
	md"""
	[`PlutoRunner.tree_data`](@ref) is overriden for [`RoseTree`](@ref) to look prettier, but that might break in the future.
	"""
end
  ╠═╡ =#

# ╔═╡ 32d817cc-9762-468a-a0f5-6356117fc46d
begin
	struct DirectedRoseTree{K, V}
		node::V
		forest::OrderedDict{K, Vector{DirectedRoseTree{K, V}}}
	end
	function DirectedRoseTree{K}(node::V)::DirectedRoseTree{K, V} where {K, V}
		DirectedRoseTree{K, V}(node)
	end
	function DirectedRoseTree{K, V}(node::V)::DirectedRoseTree{K, V} where {K, V}
		DirectedRoseTree{K, V}(node, OrderedDict{K, Vector{DirectedRoseTree{K, V}}}())
	end
	@doc """
		DirectedRoseTree{K, V}(node::V)
		DirectedRoseTree{K, V}(node::V, forest::OrderedDict{K, Vector{DirectedRoseTree{K, V}}})

	A more complex sort-of rose tree.
	""" DirectedRoseTree
end

# ╔═╡ 49248762-fb6f-4919-a719-45c0c548e858
# Base.get(tree::DirectedRoseTree, key, default) = Base.get(tree.forest, key, default)

# ╔═╡ d56600dd-461d-4d2d-9e8d-1a07d2715b95
begin
	function PlutoRunner.tree_data(@nospecialize(x::DirectedRoseTree), context::PlutoRunner.Context)
		if Base.show_circular(context, x)
			return PlutoRunner.circular(x)
		else
			depth = get(context, :tree_viewer_depth, 0)
			recur_io = PlutoRunner.IOContext(context,
				Pair{Symbol,Any}(:SHOWN_SET, x),
				Pair{Symbol,Any}(:typeinfo, Any),
				Pair{Symbol,Any}(:tree_viewer_depth, depth + 1),
			)
			recur_io_alt = PlutoRunner.IOContext(context,
				Pair{Symbol,Any}(:SHOWN_SET, x),
				Pair{Symbol,Any}(:typeinfo, Any),
				Pair{Symbol,Any}(:tree_viewer_depth, max(0, depth - 1)),
			)
	
			t = typeof(x)
	
			Dict{Symbol,Any}(
				:prefix => repr(t; context),
				:prefix_short => string(PlutoRunner.trynameof(t)),
				:objectid => PlutoRunner.objectid2str(x),
				:type => :struct,
				:elements => Any[
					(:node, PlutoRunner.format_output_default(x.node, recur_io)),
					(:forest, PlutoRunner.format_output_default(x.forest, recur_io_alt)),
				],
			)
		end
	end
	md"""
	[`PlutoRunner.tree_data`](@ref) is overriden for [`DirectedRoseTree`](@ref) to look prettier, but that might break in the future.
	"""
end

# ╔═╡ ead3a3f0-6764-4876-b8bc-64ce79499781
# ╠═╡ disabled = true
#=╠═╡
begin
	mutable struct ModulePlan
		name::String
		root::Bool
	end
	ModulePlan(name::String) = ModulePlan(name, false)
	ModulePlan
end
  ╠═╡ =#

# ╔═╡ d6ecf3e2-dbac-4478-9aa7-c9ccd230b631
const Drt = DirectedRoseTree{String, String}

# ╔═╡ 5a4e0d46-3242-4ac5-8665-de8c323b1460
function plan_execution(config::ExecuterConfig)
	analysis = analyze_module_configs(config.modules)
	include_paths_dict = Dict{String, Drt}()
	function get_include_paths(module_name::String)::Drt
		get!(() -> Drt(module_name), include_paths_dict, module_name)
	end
	root_module_names = Vector{String}()
	for module_name_to_load in config.modules_to_load
		function get_directed_include_paths(include_paths::Drt)::Vector{Drt}
			get!(() -> Vector{Drt}(undef, 0), include_paths.forest, module_name_to_load)
		end
		module_analysis = analysis.analysis[module_name_to_load]
		root_module_name = first(module_analysis)
		push!(root_module_names, root_module_name)
		root_include_paths = get_include_paths(root_module_name)
		for (mod_name, included_mod_name) in zip(module_analysis, Iterators.drop(module_analysis, 1))
			directed_include_paths = get_directed_include_paths(get_include_paths(mod_name))
			if !any(p -> (println(p.node); p.node == included_mod_name), directed_include_paths)
				push!(directed_include_paths, get_include_paths(included_mod_name))
			end
		end
	end
	plan = OrderedDict(Iterators.map(m -> m => include_paths_dict[m], unique(root_module_names)))
	(; analysis..., modules_to_load = config.modules_to_load, include_paths = include_paths_dict, plan)
end

# ╔═╡ dadaf19c-a701-4da4-a33a-58718755827d
if enable_dev_analysis @code_warntype debuginfo=:source plan_execution(executer_config_basic_simple) end

# ╔═╡ 82624852-244b-4f32-9758-b09e3f5da980
executer_config_weird_a_simple = ExecuterConfig(
	modules=Dict(sample_prelude, sample_weird_a...),
	modules_to_load=[p.first for p in (sample_weird_lower_a, sample_weird_lower_b)]
)

# ╔═╡ 379c7fa6-1863-48be-8584-dca9bf6b099e
executer_config_weird_a = ExecuterConfig(
	modules=Dict(sample_prelude, sample_weird_a...),
	modules_to_load=[p.first for p in values(sample_weird_a)]
)

# ╔═╡ 15333408-de1b-4c00-8e84-9279df6595ed
analysis_report_weird_a = report_module_configs_analysis(executer_config_weird_a.modules)

# ╔═╡ ceb63c34-1ab7-4a0f-aef8-23f97c517825
@test analysis_report_weird_a.analysis[sample_weird_lower_a.first] == [sample_prelude.first, sample_weird_upper_a.first, sample_weird_upper_b.first, sample_weird_lower_a.first]

# ╔═╡ 397a0bca-6b90-4614-a455-4fd46fd796e0
@test analysis_report_weird_a.analysis[sample_weird_lower_b.first] == [sample_prelude.first, sample_weird_upper_b.first, sample_weird_upper_a.first, sample_weird_lower_b.first]

# ╔═╡ 3419ba95-a31b-4087-96b5-3a4055d4dfff
executer_config_weird_b = ExecuterConfig(
	modules=Dict(sample_prelude, sample_weird_b...),
	modules_to_load=[p.first for p in values(sample_weird_b)]
)

# ╔═╡ 766da5df-6d7d-483a-9357-071797e47340
executer_config_weird_c = ExecuterConfig(
	modules=Dict(sample_prelude, sample_weird_c...),
	modules_to_load=[p.first for p in values(sample_weird_c)]
)

# ╔═╡ ace429e3-d667-4c6b-8179-c423af88f09d
executer_plan_weird_a = plan_execution(executer_config_weird_a)

# ╔═╡ d2e8981b-c1df-40fc-a582-6cb5717400f9
executer_plan_weird_a.plan

# ╔═╡ 9beb3cb0-ee26-4358-bbec-761315f549a1
executer_config_weird_d = ExecuterConfig(
	modules = Dict(
		"a" => ExecuterModuleConfig(including=["c"], deduplicate_inclusions=false),
		"b" => ExecuterModuleConfig(including=["d"], deduplicate_inclusions=false),
		"c" => ExecuterModuleConfig(including=["a"], deduplicate_inclusions=false),
		"d" => ExecuterModuleConfig(including=["b"], deduplicate_inclusions=false),
	),
	modules_to_load = ["c", "d"]
)

# ╔═╡ 1036338f-ce21-4b92-92b1-93a3d95499ef
executer_plan_weird_d = plan_execution(executer_config_weird_d)

# ╔═╡ e1e580ae-144a-42a1-a001-2ce172b7659f
function extract_per_module_plans(executer_plan)
	function go(module_name, t)
		if haskey(t.forest, module_name) t.node => only(Iterators.map(u -> go(module_name, u), t.forest[module_name])) else t.node end
	end
	OrderedDict(module_to_load => only(go(module_to_load, t) for (root_module, t) in executer_plan.plan) for module_to_load in executer_plan.modules_to_load)
end

# ╔═╡ d416e46c-8fd2-4ddf-a276-4e8bc8f2db93
executer_per_module_plans_weird_a = extract_per_module_plans(executer_plan_weird_a)

# ╔═╡ f4048879-5ba1-44aa-abf4-660d2b830dd1
@test executer_per_module_plans_weird_a[sample_weird_upper_a.first] == (sample_prelude.first => sample_weird_upper_a.first)

# ╔═╡ a786b68d-e883-4eda-962c-8cc2762e4c26
@test executer_per_module_plans_weird_a[sample_weird_upper_b.first] == (sample_prelude.first => sample_weird_upper_b.first)

# ╔═╡ 38c30a3e-1a44-41bf-aa85-532034ca0091
@test executer_per_module_plans_weird_a[sample_weird_lower_a.first] == (sample_prelude.first => sample_weird_upper_a.first => sample_weird_upper_b.first => sample_weird_lower_a.first)

# ╔═╡ cfaba299-3416-4c04-8c33-4c5db5b0cd67
@test executer_per_module_plans_weird_a[sample_weird_lower_b.first] == (sample_prelude.first => sample_weird_upper_b.first => sample_weird_upper_a.first => sample_weird_lower_b.first)

# ╔═╡ 9ba551de-dc76-40c1-9e84-af1315cc392a
@test length(executer_per_module_plans_weird_a) == 4

# ╔═╡ 9a846933-0ecd-49ca-beb5-7be83707c507
@test collect(keys(executer_plan_weird_a.plan)) == [sample_prelude.first]

# ╔═╡ 07c1e253-490a-4e9d-888e-cc5c01687f94
function executer_plan_funcs(executer_plan)
	include_paths_dict::Dict{String, Drt} = executer_plan.include_paths
	drt(name::String)::Drt = include_paths_dict[name]
	drt(name::Pair{String, ExecuterModuleConfig})::Drt = drt(name.first)
	drts(ts::Vararg{Pair{String, ExecuterModuleConfig}})::Vector{Drt} = [drt(t) for t in ts]
	get_forest(drt::Drt, name::String)::Vector{Drt} = drt.forest[name]
	get_forest(drt::Drt, name::Pair{String, ExecuterModuleConfig})::Vector{Drt} = get_forest(drt, name.first)
	od(args::Vararg{Pair{String, Vector{Drt}}}) = OrderedDict{String, Vector{Drt}}(args...)
	od(args::Vararg{Pair{Pair{String, ExecuterModuleConfig}, Vector{Drt}}}) = od(((name.first => ts) for (name, ts) in args)...)
	(; drt, drts, get_forest, od)
end

# ╔═╡ 88be04a5-4a28-4039-bb25-3e25c7d77235
@test executer_plan_weird_a.plan[sample_prelude.first] == Drt(sample_prelude.first, executer_plan_weird_a.plan[sample_prelude.first].forest)

# ╔═╡ 18d1d896-f873-4b49-a8ca-d24ffbf593ec
@test OrderedDict(1 => 2, 3 => 4) == OrderedDict(1 => 2, 3 => 4)

# ╔═╡ 697eee52-3c94-4278-8af2-d9fbd69cfa8a
@test executer_plan_weird_a.plan[sample_prelude.first] == Drt(sample_prelude.first, OrderedDict(pairs(executer_plan_weird_a.plan[sample_prelude.first].forest)))

# ╔═╡ 4b6eee96-5245-40b4-8ceb-1d526c9a64ae
(function ()
	f = executer_plan_funcs(executer_plan_weird_a)
	@test executer_plan_weird_a.plan[sample_prelude.first] == Drt(sample_prelude.first, f.od(
		sample_weird_upper_a => f.drts(sample_weird_upper_a),
		sample_weird_upper_b => f.drts(sample_weird_upper_b),
		sample_weird_lower_a => f.drts(sample_weird_upper_a),
		sample_weird_lower_b => f.drts(sample_weird_upper_b),
	))
end)()

# ╔═╡ 7aa9ceab-0c21-4e63-95a0-ca4b5ff326e3
executer_plan_glsl = plan_execution(executer_config_glsl)

# ╔═╡ c193028e-bc81-486b-8398-762359135f1d
executer_plan_glsl.plan

# ╔═╡ ff54c368-9b8c-41f9-b8cf-f0869a05f8ef
executer_per_module_plans_glsl = extract_per_module_plans(executer_plan_glsl)

# ╔═╡ 2b31ba5a-ec67-4411-9345-9ffdfd4aefc0
struct SimplifiedExecuterPlan
	module_name::String
	loaded_modules::Vector{SimplifiedExecuterPlan}
end

# ╔═╡ ee219df8-3eb3-4424-9c36-eb30adea859d
function simplify_executer_plan(executer_plan)
	finished = Set{String}()
	function go(drt::Drt)
		module_name = drt.node
		loaded_modules_by_name = OrderedDict{String, Vector{SimplifiedExecuterPlan}}()
		push_loaded_modules!(simplified_executer_plan::SimplifiedExecuterPlan) = append!(
			get!(() -> Vector{SimplifiedExecuterPlan}(undef, 0), loaded_modules_by_name, simplified_executer_plan.module_name),
			simplified_executer_plan.loaded_modules,
		)
		for (e, d) in pairs(drt.forest)
			for t in d
				if in(e, finished) || (e == t.node && (push!(finished, e); true))
					push_loaded_modules!(SimplifiedExecuterPlan(t.node, []))
				else
					push_loaded_modules!(go(t))
				end
			end
		end
		SimplifiedExecuterPlan(module_name, [SimplifiedExecuterPlan(n, m) for (n, m) in loaded_modules_by_name])
	end
	root_modules = values(executer_plan)
	map(go, unique(root_modules))
end

# ╔═╡ 38845954-7f41-4272-854d-f49e594c7fa2
simplify_executer_plan(executer_plan_weird_a.plan)

# ╔═╡ eab9c9e7-d3d0-479b-88bf-558e9b39be34
simplify_executer_plan(executer_plan_glsl.plan)

# ╔═╡ 534e0aa5-d158-471f-8456-9d67130b2a70
executer_plan_graphics = plan_execution(executer_config_graphics)

# ╔═╡ 29c50219-8660-4ebe-879f-b28d2a1b399a
executer_plan_graphics.plan

# ╔═╡ 6d0476f6-5e9e-4879-9738-75c25c441709
executer_per_module_plans_graphics = extract_per_module_plans(executer_plan_graphics)

# ╔═╡ 010ba51d-bba7-486c-846e-3153a8878171
simplify_executer_plan(executer_plan_graphics.plan)

# ╔═╡ 1c339f70-93d1-46f5-b7c4-b86774ad4667
function analyze_module_configs(modules::Dict{String, ExecuterModuleConfig})
	function go(module_name)
		module_config = modules[module_name]
		Iterators.flatten((
			Iterators.flatmap(go, module_config.including),
			(module_name,),
		))
	end
	full_inclusions = Dict(Iterators.map(p -> p.first => collect(unique_if(go(p.first), module_name -> modules[module_name].deduplicate_inclusions)), modules))
	(; analysis = full_inclusions)
end

# ╔═╡ 04006104-3167-45ee-a9e5-35e565681eb9
# ╠═╡ disabled = true
#=╠═╡
function analyze_module_configs(modules::Dict{String, ExecuterModuleConfig})
	full_inclusions = Dict(Iterators.map(function(p)
		module_name::String = p.first
		out = Vector{String}(undef, 0)
		dedup = Set{String}()
		seen = Set{String}()
		function go(mod_name)
			if in(mod_name, seen)
				error("cycle for $(module_name) at $(mod_name)")
			end
			push!(seen, mod_name)
			module_config = modules[mod_name]
			if in(mod_name, dedup)
				# println(mod_name)
				if !in(mod_name, seen) then
					for m in module_config.including
						go(m)
					end
				end
			else
				if module_config.deduplicate_inclusions
					push!(dedup, mod_name)
				end
				for m in module_config.including
					go(m)
				end
				push!(out, mod_name)
			end
		end
		go(module_name)
		module_name => out
	end, modules))
	(; analysis = full_inclusions)
end
  ╠═╡ =#

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
AbstractPlutoDingetjes = "6e696c72-6542-2067-7265-42206c756150"
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
DataStructures = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
HypertextLiteral = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
IterTools = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
JET = "c3a54625-cd67-489e-a8e7-0a5a0ff4e31b"
OrderedCollections = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
PlutoTest = "cb4044da-4d16-4ffa-a6a3-8cad7f73ebdc"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
PrecompileTools = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
ProfileCanvas = "efd6af41-a80b-495e-886c-e51b0c7d77a3"

[compat]
AbstractPlutoDingetjes = "~1.3.2"
BenchmarkTools = "~1.6.0"
DataStructures = "~0.18.20"
HypertextLiteral = "~0.9.5"
IterTools = "~1.10.0"
JET = "~0.9.18"
OrderedCollections = "~1.8.0"
PlutoTest = "~0.2.2"
PlutoUI = "~0.7.61"
PrecompileTools = "~1.2.1"
ProfileCanvas = "~0.1.6"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.11.3"
manifest_format = "2.0"
project_hash = "963f683cc42fb4008cea9e512bd8ff10cba7dc15"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "6e1d2a35f2f90a4bc7c2ed98079b2ba09c35b83a"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.3.2"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.2"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
version = "1.11.0"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
version = "1.11.0"

[[deps.BenchmarkTools]]
deps = ["Compat", "JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "e38fbc49a620f5d0b660d7f543db1009fe0f8336"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.6.0"

[[deps.CodeTracking]]
deps = ["InteractiveUtils", "UUIDs"]
git-tree-sha1 = "7eee164f122511d3e4e1ebadb7956939ea7e1c77"
uuid = "da1fd8a2-8d9e-5ec2-8556-3022fb5608a2"
version = "1.3.6"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "b10d0b65641d57b8b4d5e234446582de5047050d"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.5"

[[deps.Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "8ae8d32e09f0dcf42a36b90d4e17f5dd2e4c4215"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.16.0"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.1.1+0"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "1d0a14036acb104d9e89698bd408f63ab58cdc82"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.20"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"
version = "1.11.0"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "05882d6995ae5c12bb5f36dd2ed3f61c98cbb172"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.5"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "7134810b1afce04bbc1045ca1985fbe81ce17653"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.5"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "b6d6bfdd7ce25b0f9b2f6b3dd56b2673a66c8770"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.5"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
version = "1.11.0"

[[deps.IterTools]]
git-tree-sha1 = "42d5f897009e7ff2cf88db414a389e5ed1bdd023"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.10.0"

[[deps.JET]]
deps = ["CodeTracking", "InteractiveUtils", "JuliaInterpreter", "JuliaSyntax", "LoweredCodeUtils", "MacroTools", "Pkg", "PrecompileTools", "Preferences", "Test"]
git-tree-sha1 = "a453c9b3320dd73f5b05e8882446b6051cb254c4"
uuid = "c3a54625-cd67-489e-a8e7-0a5a0ff4e31b"
version = "0.9.18"

    [deps.JET.extensions]
    JETCthulhuExt = "Cthulhu"
    JETReviseExt = "Revise"

    [deps.JET.weakdeps]
    Cthulhu = "f68482b8-f384-11e8-15f7-abe071a5a75f"
    Revise = "295af30f-e4ad-537b-8983-00126c2a3abe"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JuliaInterpreter]]
deps = ["CodeTracking", "InteractiveUtils", "Random", "UUIDs"]
git-tree-sha1 = "4bf4b400a8234cff0f177da4a160a90296159ce9"
uuid = "aa1ae85d-cabe-5617-a682-6adf51b2e16a"
version = "0.9.41"

[[deps.JuliaSyntax]]
git-tree-sha1 = "937da4713526b96ac9a178e2035019d3b78ead4a"
uuid = "70703baa-626e-46a2-a12c-08ffd08c73b4"
version = "0.4.10"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.6.0+0"

[[deps.LibGit2]]
deps = ["Base64", "LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"
version = "1.11.0"

[[deps.LibGit2_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.7.2+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.0+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
version = "1.11.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
version = "1.11.0"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
version = "1.11.0"

[[deps.LoweredCodeUtils]]
deps = ["JuliaInterpreter"]
git-tree-sha1 = "688d6d9e098109051ae33d126fcfc88c4ce4a021"
uuid = "6f1432cf-f94c-5a45-995e-cdbf5db27b0b"
version = "3.1.0"

[[deps.MIMEs]]
git-tree-sha1 = "1833212fd6f580c20d4291da9c1b4e8a655b128e"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "1.0.0"

[[deps.MacroTools]]
git-tree-sha1 = "72aebe0b5051e5143a079a4685a46da330a40472"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.15"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
version = "1.11.0"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.6+0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"
version = "1.11.0"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2023.12.12"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.27+1"

[[deps.OrderedCollections]]
git-tree-sha1 = "cc4054e898b852042d7b503313f7ad03de99c3dd"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.8.0"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "8489905bcdbcfac64d1daa51ca07c0d8f0283821"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.1"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "Random", "SHA", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.11.0"
weakdeps = ["REPL"]

    [deps.Pkg.extensions]
    REPLExt = "REPL"

[[deps.PlutoTest]]
deps = ["HypertextLiteral", "InteractiveUtils", "Markdown", "Test"]
git-tree-sha1 = "17aa9b81106e661cffa1c4c36c17ee1c50a86eda"
uuid = "cb4044da-4d16-4ffa-a6a3-8cad7f73ebdc"
version = "0.2.2"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "7e71a55b87222942f0f9337be62e26b1f103d3e4"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.61"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "5aa36f7049a63a1528fe8f7c3f2113413ffd4e1f"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.2.1"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "9306f6085165d270f7e3db02af26a400d580f5c6"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.4.3"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
version = "1.11.0"

[[deps.Profile]]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"
version = "1.11.0"

[[deps.ProfileCanvas]]
deps = ["Base64", "JSON", "Pkg", "Profile", "REPL"]
git-tree-sha1 = "e42571ce9a614c2fbebcaa8aab23bbf8865c624e"
uuid = "efd6af41-a80b-495e-886c-e51b0c7d77a3"
version = "0.1.6"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "StyledStrings", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"
version = "1.11.0"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
version = "1.11.0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
version = "1.11.0"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"
version = "1.11.0"

[[deps.Statistics]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "ae3bb1eb3bba077cd276bc5cfc337cc65c3075c0"
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.11.1"

    [deps.Statistics.extensions]
    SparseArraysExt = ["SparseArrays"]

    [deps.Statistics.weakdeps]
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.StyledStrings]]
uuid = "f489334b-da3d-4c2e-b8f0-e476e12c162b"
version = "1.11.0"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
version = "1.11.0"

[[deps.Tricks]]
git-tree-sha1 = "6cae795a5a9313bbb4f60683f7263318fc7d1505"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.10"

[[deps.URIs]]
git-tree-sha1 = "67db6cc7b3821e19ebe75791a9dd19c9b1188f2b"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.5.1"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
version = "1.11.0"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
version = "1.11.0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+1"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.11.0+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.59.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+2"
"""

# ╔═╡ Cell order:
# ╟─b818d46b-d26d-4e99-a16d-05931474b0fb
# ╟─a92297ee-6754-4ece-ba7d-9aa1fb30365c
# ╟─065ccb13-c395-45d9-92e6-2fafd9f21520
# ╠═2633e081-eb6f-4678-a17c-b5f6d2e92812
# ╠═c02f8f2a-3669-4663-ba92-4ac307e5f456
# ╠═d7ecd0d5-0073-456c-9d1b-48840272120a
# ╠═4faef874-6865-4f25-a6df-35ea0118d3d0
# ╟─e27594f1-a61b-4660-b315-be91ea52ccbd
# ╟─d5ac852e-f0e9-49b2-8510-0a969289f7a9
# ╟─7c7bf62e-874d-472a-bc04-b11792594f66
# ╠═14bd1588-e550-44f9-ae35-470d93a805db
# ╠═f5da097a-e629-4395-8f66-bfe9bf0da3df
# ╟─23acf665-9b8f-481f-acc8-b2f6af1409c8
# ╠═1f8630a1-8a03-40db-bd8f-96c33e2b8aea
# ╠═0c1d47a7-5e6f-4928-ba05-0782d77b99ae
# ╠═e7b57e0b-896a-4b96-a69a-6e75e6e9d0ca
# ╠═dc52a346-7e6e-4891-a42d-a2c760e33af4
# ╠═53c8e07a-ba00-443a-b627-304dd97f3389
# ╠═f61ff882-2760-4bb3-82e8-c3e875778498
# ╠═9aff452c-7119-4d22-a009-1ab5d55e9ab8
# ╠═7d789b92-c028-46c7-a1f0-64b5890382be
# ╟─e17d1e30-8808-42db-a008-e0274fe51b5d
# ╠═d1aef33c-f78b-4088-93bd-8a34962e15bf
# ╠═69ff6ed6-639f-460a-a006-a997d09d4853
# ╠═8241948a-a280-4b0a-bde2-3783cd4af369
# ╟─4ed223ba-7f1f-4def-bbd2-ba63eb0e65de
# ╠═05793160-6ad3-4a40-b6dd-7f89ff877fc7
# ╠═3d0ad692-f004-4071-b797-6df5df8df996
# ╠═7ebf4e23-9950-4131-bb0b-e9783d0cf9ed
# ╟─c7a45c69-21e0-4115-8ff6-f305ecfc5b2e
# ╠═2c8395c4-eedf-4e18-b649-8cf11773a008
# ╠═f96385f3-4480-4464-97cb-0f0c692ba106
# ╠═3cae07f7-ca03-4d97-a4f8-1c647f07333b
# ╠═439437d8-7e17-4b76-97b5-c373d7db4d4c
# ╠═4b837942-d0fb-4327-8de7-e1f32ee03722
# ╟─7319c765-6466-4499-86df-9c586ec58ca3
# ╠═631efdc5-5940-4e8a-9c16-342dc66e9ce4
# ╠═1c339f70-93d1-46f5-b7c4-b86774ad4667
# ╠═04006104-3167-45ee-a9e5-35e565681eb9
# ╠═bba836c3-7545-40b5-8406-e465e151fcc0
# ╠═01e3d956-3d28-464f-b74b-1d109ef141d5
# ╠═15333408-de1b-4c00-8e84-9279df6595ed
# ╠═ceb63c34-1ab7-4a0f-aef8-23f97c517825
# ╠═397a0bca-6b90-4614-a455-4fd46fd796e0
# ╠═245ab575-a43e-4d34-9e1d-a6286812c2a7
# ╠═a3d5d045-4ae1-4993-b3c7-7afa81da83ee
# ╟─4759265b-a970-4623-8b7b-e3357159ae58
# ╠═32d817cc-9762-468a-a0f5-6356117fc46d
# ╠═49248762-fb6f-4919-a719-45c0c548e858
# ╟─d56600dd-461d-4d2d-9e8d-1a07d2715b95
# ╟─ead3a3f0-6764-4876-b8bc-64ce79499781
# ╠═d6ecf3e2-dbac-4478-9aa7-c9ccd230b631
# ╠═5a4e0d46-3242-4ac5-8665-de8c323b1460
# ╠═dadaf19c-a701-4da4-a33a-58718755827d
# ╠═82624852-244b-4f32-9758-b09e3f5da980
# ╟─379c7fa6-1863-48be-8584-dca9bf6b099e
# ╟─3419ba95-a31b-4087-96b5-3a4055d4dfff
# ╟─766da5df-6d7d-483a-9357-071797e47340
# ╠═ace429e3-d667-4c6b-8179-c423af88f09d
# ╠═d2e8981b-c1df-40fc-a582-6cb5717400f9
# ╠═38845954-7f41-4272-854d-f49e594c7fa2
# ╠═9beb3cb0-ee26-4358-bbec-761315f549a1
# ╠═1036338f-ce21-4b92-92b1-93a3d95499ef
# ╠═e1e580ae-144a-42a1-a001-2ce172b7659f
# ╠═d416e46c-8fd2-4ddf-a276-4e8bc8f2db93
# ╠═f4048879-5ba1-44aa-abf4-660d2b830dd1
# ╠═a786b68d-e883-4eda-962c-8cc2762e4c26
# ╠═38c30a3e-1a44-41bf-aa85-532034ca0091
# ╠═cfaba299-3416-4c04-8c33-4c5db5b0cd67
# ╠═9ba551de-dc76-40c1-9e84-af1315cc392a
# ╠═9a846933-0ecd-49ca-beb5-7be83707c507
# ╠═07c1e253-490a-4e9d-888e-cc5c01687f94
# ╠═88be04a5-4a28-4039-bb25-3e25c7d77235
# ╠═18d1d896-f873-4b49-a8ca-d24ffbf593ec
# ╠═697eee52-3c94-4278-8af2-d9fbd69cfa8a
# ╠═4b6eee96-5245-40b4-8ceb-1d526c9a64ae
# ╠═7aa9ceab-0c21-4e63-95a0-ca4b5ff326e3
# ╠═c193028e-bc81-486b-8398-762359135f1d
# ╠═ff54c368-9b8c-41f9-b8cf-f0869a05f8ef
# ╠═2b31ba5a-ec67-4411-9345-9ffdfd4aefc0
# ╠═ee219df8-3eb3-4424-9c36-eb30adea859d
# ╠═eab9c9e7-d3d0-479b-88bf-558e9b39be34
# ╠═534e0aa5-d158-471f-8456-9d67130b2a70
# ╠═29c50219-8660-4ebe-879f-b28d2a1b399a
# ╠═6d0476f6-5e9e-4879-9738-75c25c441709
# ╠═010ba51d-bba7-486c-846e-3153a8878171
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
