import Foundation

// MARK: - Sample Stories
// TODO: Replace this file's return value with a real news-API call + Codable mapping.

let sampleStories: [Story] = [

    // ── 1. Neuromorphic chips ────────────────────────────────────────────────
    Story(
        id: "neuro-chips",
        source: "Circuit",
        mono: "CI",
        category: "SEMICONDUCTOR",
        readTime: "6 min",
        author: "Dr. Elena Whitfield",
        date: "Jun 24, 2025",
        title: "The brain-like chips trying to save AI from itself",
        summary: "As transformer models demand ever-more megawatts, a clutch of startups is betting that mimicking biological neurons is the only path left.",
        imageURL: "https://images.unsplash.com/photo-1518770660439-4636190af475?w=1000&q=80&auto=format&fit=crop",
        likes: 3_412,
        hue: 0.60,
        chatIntro: "neuromorphic hardware could cut AI inference power by 1000× — but it rewrites every software assumption you have.",
        blocks: [
            .lead("A single GPT-4-class training run consumes more electricity than 130 average American homes use in a year. The next generation model will need four times that. Something has to give."),
            .heading("The von Neumann wall"),
            .paragraph("Every modern AI accelerator — Nvidia's H100, Google's TPU, Amazon's Trainium — is built on the same 80-year-old assumption: memory and compute live in separate places and data must shuttle between them. For large neural networks, that shuttle costs most of the energy. **Intel's Loihi 3 and IBM's NorthPole chip** break that wall by embedding memory directly inside each artificial neuron."),
            .quote(text: "We are not making a faster GPU. We are making a different animal entirely.", cite: "Dr. Kwabena Boahen, Stanford Neurogrid Lab"),
            .image(url: "https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?w=1000&q=80&auto=format&fit=crop",
                   caption: "A wafer of neuromorphic cores under inspection at Intel's fabrication lab, Hillsboro OR."),
            .heading("Spikes, not floats"),
            .paragraph("Biological neurons don't stream 32-bit floats. They fire discrete voltage spikes — and only when they need to. **Spiking Neural Networks (SNNs)** mimic this behaviour. Between spikes, most transistors sit idle, consuming near-zero power. Benchmarks from BrainChip's Akida chip show a 50× improvement in inference-per-watt over an equivalent CUDA GPU on keyword detection tasks."),
            .table(
                head: ["Chip", "Peak TOPS", "Inference W", "Arch"],
                rows: [
                    ["Nvidia H100", "3958", "700 W", "CUDA / SIMT"],
                    ["Intel Loihi 3", "~10", "< 1 W", "Spiking NN"],
                    ["IBM NorthPole", "~22", "~74 W", "Near-memory"],
                    ["BrainChip Akida", "~5", "< 0.5 W", "Spiking NN"],
                ]
            ),
            .heading("The software problem"),
            .paragraph("Hardware is the easy part. The hard part is **rewriting decades of frameworks**. PyTorch, JAX, and TensorFlow have no SNN primitives. Startups like SpiNNcloud and Innatera are building thin compiler layers, but adoption is measured in PhD theses, not production deployments. Hyperscalers are watching but not yet writing cheques."),
            .diagram(title: "HOW A SPIKING NEURON FIRES", steps: [
                "**Dendrites** accumulate weighted input signals from upstream neurons",
                "Membrane potential rises toward a **threshold voltage**",
                "At threshold, neuron fires a **spike** — a brief 1 ms voltage pulse",
                "Spike travels axon to downstream neurons; local potential **resets to zero**",
                "Between spikes the transistor is **fully idle** — zero dynamic power draw",
            ]),
            .paragraph("The window is narrow. If SNN compilers don't reach production quality before the next GPU generation ships, the momentum could swing back to brute-force silicon. But if they do, the 2030 data-centre might look radically different — not a field of server racks humming at megawatt scale, but something quieter and stranger."),
        ],
        prompts: [
            Prompt(question: "What is a spiking neural network?",
                   answer: "Unlike standard neural nets that pass continuous floating-point values, SNNs communicate via discrete voltage spikes — just like biological neurons. Compute only happens during a spike; transistors are idle otherwise, which is why power consumption can be orders of magnitude lower."),
            Prompt(question: "Why haven't big companies adopted this yet?",
                   answer: "The software ecosystem is immature. PyTorch and JAX have no native SNN support, and porting existing models requires retraining from scratch. Hyperscalers also have massive sunk costs in GPU-optimised infrastructure and CUDA-trained engineers."),
            Prompt(question: "When could this realistically reach data centres?",
                   answer: "Industry analysts put meaningful hyperscaler adoption at 2028–2031, contingent on a PyTorch-compatible SNN compiler reaching production stability. Intel and IBM both have roadmaps targeting 2026 for inference-only workloads in niche domains like edge robotics."),
        ],
        bodyHTML: ReaderContent.neuroChips
    ),

    // ── 2. Robotics branding ─────────────────────────────────────────────────
    Story(
        id: "robotics-boom",
        source: "Stratum",
        mono: "ST",
        category: "VENTURE",
        readTime: "5 min",
        author: "Marcus Feld",
        date: "Jun 19, 2025",
        title: "Why every startup is suddenly a robotics company",
        summary: "From laundry folding to last-mile delivery, the 'robot' label has become the fastest route to a Series A — and investors are beginning to notice the pattern.",
        imageURL: "https://images.unsplash.com/photo-1485827404703-89b55fcc595e?w=1000&q=80&auto=format&fit=crop",
        likes: 2_188,
        hue: 0.08,
        chatIntro: "the robotics label is the new 'AI-powered' — a fundraising shorthand that papers over wildly different business models.",
        blocks: [
            .lead("In Q1 2025, 41 % of all seed rounds in the US hardware sector went to companies with 'robot', 'autonomous', or 'embodied AI' in their pitch deck. Three years ago that figure was 9 %."),
            .heading("The label does the work"),
            .paragraph("Venture partners who once demanded five years of commercial traction are now writing cheques on the promise of **general-purpose manipulation**. The cause is a confluence: Boston Dynamics demonstrating bipedal warehouse work, Figure AI's BMW deal, and — most crucially — the viral moment when 1X's NEO robot folded a T-shirt on camera without a teleoperation rig in sight."),
            .quote(text: "Every founder we meet now claims their software 'runs on any robot'. That's usually code for 'we haven't shipped hardware yet'.", cite: "Partner, Tier 1 deep-tech VC (anonymous)"),
            .image(url: "https://images.unsplash.com/photo-1563207153-f403bf289096?w=1000&q=80&auto=format&fit=crop",
                   caption: "Humanoid arms assembling consumer electronics at a pilot line in Shenzhen, 2025."),
            .heading("What actually ships"),
            .paragraph("Strip away the press releases and the pattern becomes clear. **Tier 1**: genuine full-stack robotics companies with actuators, firmware, and trained motion policies (Agility, Figure, 1X). **Tier 2**: software wrappers selling 'robot-agnostic' orchestration layers that require the customer to already own hardware. **Tier 3**: SaaS companies that swapped 'workflow automation' for 'agentic robot orchestration' in their marketing copy after a consultant's advice."),
            .table(
                head: ["Tier", "Ships hardware?", "Median raise", "Survival rate (3 yr)"],
                rows: [
                    ["Full-stack OEM", "Yes", "$120 M", "~38 %"],
                    ["Software / SDK", "No", "$18 M", "~52 %"],
                    ["Relabelled SaaS", "No", "$6 M", "~21 %"],
                ]
            ),
            .diagram(title: "ANATOMY OF A ROBOTICS ROUND", steps: [
                "Founder posts **viral clip** of prototype performing one task flawlessly",
                "Clip surfaces in partner Slack — associate schedules intro call same day",
                "Deck lands with 'embodied AI' and 'physical world foundation model' in first slide",
                "**Term sheet** offered before pilot customer is named; valuation: 40× projected ARR",
                "12 months later: **pivot to software**, hardware 'paused pending cost reduction'",
            ]),
            .paragraph("None of this means the category is a fraud. Genuine breakthroughs in learned motor control mean robots that would have cost $2 M to build in 2019 now cost $180 K. But **investor pattern-matching on aesthetics** — exoskeletons, bipedal frames, glossy white plastic — risks misdirecting capital away from the unglamorous picks-and-shovels companies actually enabling the ecosystem."),
        ],
        prompts: [
            Prompt(question: "Which robotics companies are actually shipping?",
                   answer: "Agility Robotics (Digit, in Amazon fulfillment centres), Figure AI (BMW pilot line), 1X Technologies (NEO in office environments), and Boston Dynamics (Spot, widely deployed in inspection). Most others are pre-commercial or shipping software SDKs only."),
            Prompt(question: "Why do investors fall for the label?",
                   answer: "FOMO from the Boston Dynamics acquisition premium ($1.1B) and Figure's $2.6B valuation on near-zero revenue. Also, embodied AI is genuinely hard to diligence quickly — a flashy demo can obscure years away from commercial viability."),
            Prompt(question: "What's the actual bottleneck for humanoid robots?",
                   answer: "Dexterous manipulation in unstructured environments. Sorting known SKUs on a conveyor is solved. Picking arbitrary objects from a bin in a new layout — the 'bin picking generalisation problem' — still fails at unacceptable rates outside controlled pilots."),
        ]
    ),

    // ── 3. Undersea data centres ─────────────────────────────────────────────
    Story(
        id: "sea-datacenters",
        source: "Terminal",
        mono: "TE",
        category: "INFRASTRUCTURE",
        readTime: "5 min",
        author: "Priya Raman",
        date: "Jun 12, 2025",
        title: "Inside the data centers that cool themselves with the sea",
        summary: "As AI demand outpaces the grid, operators are sinking compute beneath the waves — and rewriting the economics of the cloud in the process.",
        imageURL: "https://images.unsplash.com/photo-1558494949-ef010cbdcc31?w=1000&q=80&auto=format&fit=crop",
        likes: 2_104,
        hue: 0.55,
        chatIntro: "submerged data centres aren't a gimmick — they solve three of the five hardest problems in hyperscale compute simultaneously.",
        blocks: [
            .lead("The numbers that keep data-centre operators awake are no longer about storage. They are about **heat**, and **water**, and the rising cost of getting rid of both."),
            .heading("Project Natick's second act"),
            .paragraph("Microsoft's Project Natick dropped a pressurised steel cylinder off the Orkney Islands in 2018 and retrieved it two years later with a **failure rate eight times lower** than equivalent surface data centres. Fewer thermal cycles, no human-introduced contamination, and ambient seawater at 10 °C doing the cooling work for free. The project was quietly shelved — then revived in 2024 when AI inference workloads made the heat math untenable on land."),
            .quote(text: "The ocean is the world's largest heat sink. The question was never whether it works. The question was whether the economics close.", cite: "Ben Cutler, Microsoft Natick Program Manager"),
            .image(url: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=1000&q=80&auto=format&fit=crop",
                   caption: "Pressurised subsea modules being tested at depth off the coast of the Faroe Islands, early 2025."),
            .heading("The thermal arithmetic"),
            .paragraph("A rack of Nvidia H100s at full load produces roughly **10 kW of heat per rack unit**. A 1 MW data-centre pod — modest by hyperscale standards — requires cooling systems that in a desert facility consume 40 % of total power. Seawater at depth stays near 4 °C year-round. Run seawater through a heat exchanger bolted to the outside of a submersible pressure vessel and the cooling bill approaches zero. **PUE (Power Usage Effectiveness) drops from the industry average of 1.55 to below 1.08.**"),
            .table(
                head: ["Metric", "Land (desert)", "Land (Nordic)", "Subsea"],
                rows: [
                    ["PUE", "1.55", "1.20", "< 1.08"],
                    ["Water Use (L/MWh)", "1 800", "400", "0"],
                    ["Land cost / MW", "$4.2 M", "$2.8 M", "$0"],
                    ["Avg failure rate", "4 %/yr", "3.5 %/yr", "< 0.5 %/yr"],
                ]
            ),
            .diagram(title: "HOW A SUBSEA POD WORKS", steps: [
                "**Pressure vessel** (steel cylinder, 2 atm N₂ atmosphere) houses compute racks",
                "Servers exhaust heat into **internal coolant loop** — no open air circulation",
                "Internal loop transfers heat to **seawater heat exchanger** on vessel exterior",
                "Cold seawater (4–10 °C) absorbs heat and is **discharged 50 m downstream**",
                "Power and fibre reach vessel via **armoured subsea cable** from shore",
                "Vessel **retrieved every 5 years** for hardware refresh; no on-site maintenance",
            ]),
            .paragraph("The remaining unsolved problems are regulatory, not engineering. Subsea deployments fall under a patchwork of maritime law, environmental-impact rules, and fishing-zone agreements that vary by exclusive economic zone. **Permitting a single pod off California currently takes 3–5 years.** Norway and Iceland — with streamlined EEZ rules and cold Atlantic waters — are emerging as the obvious first commercial hosts."),
        ],
        prompts: [
            Prompt(question: "What happened to Microsoft's original Natick project?",
                   answer: "Phase 2 concluded in 2020 and confirmed the hardware reliability gains. Microsoft didn't productise it immediately — the economics weren't compelling enough when AI training workloads were still manageable on land. The 2024 AI inference surge changed that calculus."),
            Prompt(question: "Is this environmentally safe?",
                   answer: "Discharged seawater is several degrees warmer than ambient, which can affect local marine ecosystems if discharge is concentrated. Modern designs disperse over a wide area to stay within thermal pollution limits. Compared to freshwater consumption of land data centres — a genuine scarcity issue in drought-prone regions — the environmental trade-off often favours subsea."),
            Prompt(question: "How much would a subsea data centre cost?",
                   answer: "Current estimates from Microsoft and Deep Green (a UK startup doing submerged compute) put build cost at roughly $8–12 M per MW — about 2–2.5× a standard land build. The payback comes from eliminated cooling OPEX (roughly $1.2 M/yr per MW saved) and avoided land costs in premium coastal markets."),
        ]
    ),

    // ── 4. Four-day week economics ───────────────────────────────────────────
    Story(
        id: "four-day-week",
        source: "Ledger",
        mono: "LE",
        category: "LABOUR",
        readTime: "4 min",
        author: "James Okafor",
        date: "Jun 5, 2025",
        title: "The four-day week is winning — just not how anyone expected",
        summary: "After three years of pilots, the productivity data is in. The companies that succeeded aren't working smarter. They're working differently.",
        imageURL: "https://images.unsplash.com/photo-1497366216548-37526070297c?w=1000&q=80&auto=format&fit=crop",
        likes: 4_871,
        hue: 0.12,
        chatIntro: "the four-day week works, but the mechanism isn't what advocates claimed — it's not about hours, it's about meeting culture.",
        blocks: [
            .lead("The UK's landmark 2023 four-day-week trial ended with 89 % of companies making it permanent. Three years on, the data tells a more nuanced story than either advocates or sceptics predicted."),
            .heading("The productivity paradox"),
            .paragraph("The standard argument for a compressed week is that focused workers produce more in four days than distracted workers produce in five. The data partially backs this: **revenue per employee rose an average of 8 %** across the 61 UK companies that completed the trial. But the mechanism isn't what anyone expected. Fewer hours alone didn't do it. The gains almost entirely came from two sources: **a 34 % reduction in internal meetings** and a dramatic drop in voluntary turnover — from 11 % annually to 4 %."),
            .quote(text: "We didn't get more productive by working less. We got more productive by being forced to decide what actually needed a meeting.", cite: "Charlotte Lockhart, 4 Day Week Global"),
            .image(url: "https://images.unsplash.com/photo-1542744173-8e7e53415bb0?w=1000&q=80&auto=format&fit=crop",
                   caption: "A distributed team's Friday 'no-meeting' experiment evolved into a company-wide policy that outlasted the pilot."),
            .heading("Who wins and who doesn't"),
            .paragraph("The gains are not evenly distributed. **Professional services firms, software companies, and marketing agencies** — where output is measurable and async communication is natural — saw the strongest results. **Manufacturing, retail, and healthcare** had near-zero adoption, not for productivity reasons, but because the five-day week is baked into customer expectations, shift scheduling, and regulatory requirements. A hospital can't close its A&E on Fridays."),
            .table(
                head: ["Sector", "4DW adoption (2025)", "Revenue Δ", "Turnover Δ"],
                rows: [
                    ["Software / Tech", "41 %", "+11 %", "−62 %"],
                    ["Professional Services", "29 %", "+7 %", "−55 %"],
                    ["Marketing / Creative", "37 %", "+9 %", "−58 %"],
                    ["Retail", "3 %", "Flat", "−8 %"],
                    ["Manufacturing", "2 %", "Flat", "−5 %"],
                ]
            ),
            .diagram(title: "THE FOUR-DAY FLYWHEEL", steps: [
                "**Day 5 removed** — teams audit every recurring meeting for necessity",
                "**Meeting count drops** 30–40 %; async documentation improves as a side-effect",
                "Focus blocks increase; deep work output rises **within weeks**",
                "**Turnover falls** — talent retention lowers recruiting costs dramatically",
                "Savings fund benefits, compensation, or further headcount — **cycle reinforces**",
            ]),
            .paragraph("The least-discussed effect is on **hiring**. Companies offering a four-day week at equal pay report receiving 3–5× more qualified applicants per role than competitors. In a labour market where software engineers can choose between dozens of equivalent offers, the compressed week has become a **decisive differentiator** — worth, by some estimates, the equivalent of a $15–20 K salary premium."),
        ],
        prompts: [
            Prompt(question: "Does this only work for remote companies?",
                   answer: "No, but it's easier for them. In-office companies in the UK trial also succeeded — the key was redesigning processes, not location. Several manufacturing-adjacent companies succeeded by rotating four-day shifts rather than compressing a five-day schedule."),
            Prompt(question: "What's the failure mode?",
                   answer: "The most common failure is 'silent compression' — work that used to take five days now happens in four days at higher intensity, with no meeting reduction or process redesign. Burnout rises and the trial collapses. Successful implementations mandated a minimum 25% reduction in scheduled meetings as a precondition."),
            Prompt(question: "Will this become legally required anywhere?",
                   answer: "Belgium already allows employees to request a four-day week (same hours compressed). Scotland's SNP government ran a pilot. Spain offered tax incentives. Full legal mandates — like the 35-hour week in France — are unlikely outside Northern Europe in the near term."),
        ]
    ),

    // ── 5. Small banks + AI agents ───────────────────────────────────────────
    Story(
        id: "bank-ai-agents",
        source: "Clearing",
        mono: "CL",
        category: "FINTECH",
        readTime: "6 min",
        author: "Sofia Delgado",
        date: "May 28, 2025",
        title: "The small banks betting their back office on AI agents",
        summary: "While JPMorgan deploys armies of engineers, community banks are quietly automating compliance, lending, and reconciliation with a handful of API calls.",
        imageURL: "https://images.unsplash.com/photo-1501167786227-4cba60f6d58f?w=1000&q=80&auto=format&fit=crop",
        likes: 1_933,
        hue: 0.35,
        chatIntro: "community banks are leapfrogging big bank tech debt by going straight to AI agents — a 'leapfrog' dynamic not seen since mobile banking in emerging markets.",
        blocks: [
            .lead("First National Bank of Abilene has 14 branches, $2.3 billion in assets, and — as of March 2025 — no compliance officers on the back-shift. An AI agent reads every transaction overnight and files the SARs by morning."),
            .heading("The tech debt advantage"),
            .paragraph("Big banks are not slow to adopt AI because they lack ambition. They are slow because **every process touches a core banking system written in COBOL in 1987** that nobody alive fully understands. Community banks, by contrast, migrated to modern cloud cores (Finxact, Thought Machine, Temenos) in the 2018–2022 wave. Their data is clean, structured, and API-accessible. Drop an agent on top and the automation almost writes itself."),
            .quote(text: "We don't have a hundred million lines of legacy code to protect. That makes us faster than Wells Fargo, not slower.", cite: "Pamela Cruz, CTO, First National Bank of Abilene"),
            .image(url: "https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?w=1000&q=80&auto=format&fit=crop",
                   caption: "A community bank operations centre — most of the screens now display agent activity logs, not human dashboards."),
            .heading("What the agents actually do"),
            .paragraph("The most commercially mature use cases cluster around **rule-heavy, document-heavy tasks** where the decision criteria are known but the labour is expensive and error-prone. Anti-money-laundering transaction monitoring, BSA/AML narrative generation, commercial loan covenant tracking, GL reconciliation, and Reg CC hold calculations. None of these require judgment calls — they require **exhaustive rule application at scale**, which is precisely what a well-prompted LLM with function-calling excels at."),
            .table(
                head: ["Use case", "Prev. FTE cost", "Agent cost/mo", "Error rate Δ"],
                rows: [
                    ["SAR filing (AML)", "$18 K / mo", "$1 200", "−44 %"],
                    ["Covenant tracking", "$9 K / mo", "$600", "−71 %"],
                    ["GL reconciliation", "$22 K / mo", "$1 800", "−38 %"],
                    ["Reg CC holds calc.", "$6 K / mo", "$400", "−55 %"],
                ]
            ),
            .diagram(title: "HOW AN AML AGENT WORKS", steps: [
                "**Core banking API** streams flagged transactions nightly to agent context",
                "Agent **retrieves customer history** and cross-references sanctions lists via tool call",
                "Agent **drafts SAR narrative** following FinCEN template — cites transactions by ID",
                "**Compliance officer reviews** pre-filled draft; approves or edits in < 4 minutes",
                "Agent **files electronically** via BSA E-Filing API; logs decision for audit trail",
            ]),
            .paragraph("The regulatory risk is real but manageable. The OCC has issued guidance that AI-assisted compliance is permissible provided a **licensed human reviews and signs off** every filed report. The agent doesn't replace the compliance officer — it replaces the 11-hour overnight shift of reading transaction logs and drafting from scratch. The officer arrives to a queue of annotated, near-complete filings. **That's the product.**"),
        ],
        prompts: [
            Prompt(question: "What's the biggest risk of this approach?",
                   answer: "Hallucinated citations in SAR narratives — the agent confidently referencing a transaction ID that doesn't exist or misattributing a date. Mitigated by grounding the agent strictly in the actual transaction data passed as structured context rather than relying on the model's memory. Human review catches the rest."),
            Prompt(question: "What LLMs are these banks using?",
                   answer: "Mostly Claude and GPT-4o via private API agreements with Azure OpenAI (for HIPAA-adjacent compliance reasons). A minority run open-weight models (Llama 3, Mistral) on-prem to avoid sending customer data to third-party endpoints. The on-prem route is cheaper at scale but requires ML ops capacity most community banks don't have."),
            Prompt(question: "Could this threaten back-office jobs?",
                   answer: "In the narrow sense, yes — SAR analyst headcount at piloting banks dropped 30–50%. But banks consistently report redeploying those staff to relationship banking and SME lending where human judgment genuinely matters. Whether that redeployment holds industry-wide as adoption scales is the open question regulators and unions are watching."),
        ]
    ),
]
