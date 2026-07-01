import SwiftUI
import WebKit

// MARK: - DetailView (premium HTML reader)
// The article body is real HTML rendered in a WKWebView with the Curio house
// stylesheet — so it can show anything the web can (rich text, lists, tables,
// figures, code, blockquotes, and custom SVG/canvas/JS visualizations) while
// staying consistently premium and on-brand. Hero + byline + body all live in
// the web layer (one scroll surface); the back chevron, reading-progress bar,
// and the swipe morph transition stay native. Dismiss-swipe is a UIKit pan on
// the web view's scroll view (gated to rightward-horizontal) so vertical
// reading never contends with it.
struct DetailView: View {
    let story: Story
    let onCloseDragChanged: (CGFloat) -> Void
    let onCloseDragEnded: (CGFloat, CGFloat) -> Void
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.safeTop) private var safeTop
    @Environment(\.safeBottom) private var safeBottom
    @State private var readProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                theme.pageBg.ignoresSafeArea()

                WebArticleView(
                    html: ReaderHTML.page(for: story, safeTop: safeTop, safeBottom: safeBottom),
                    onScrollProgress: { readProgress = $0 },
                    onCloseDragChanged: onCloseDragChanged,
                    onCloseDragEnded: onCloseDragEnded
                )
                .ignoresSafeArea()

                // Reading-progress bar, pinned to the very top.
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: max(0, geo.size.width * readProgress), height: 2.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)

                // Always-available way back (in addition to swipe-right).
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.top, safeTop + 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - WebArticleView (WKWebView wrapper)
private struct WebArticleView: UIViewRepresentable {
    let html: String
    let onScrollProgress: (CGFloat) -> Void
    let onCloseDragChanged: (CGFloat) -> Void
    let onCloseDragEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 8/255, green: 9/255, blue: 11/255, alpha: 1)   // pageBg
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.contentInsetAdjustmentBehavior = .never   // hero sits under the status bar
        web.scrollView.delegate = context.coordinator
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false

        // Dismiss-swipe as a UIKit pan so it never fights vertical reading scroll.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleClosePan(_:)))
        pan.delegate = context.coordinator
        web.scrollView.addGestureRecognizer(pan)

        context.coordinator.loadedHTML = html
        web.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }   // only reload on real change
        context.coordinator.loadedHTML = html
        web.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, WKNavigationDelegate, UIGestureRecognizerDelegate {
        let parent: WebArticleView
        var loadedHTML: String?
        init(_ parent: WebArticleView) { self.parent = parent }

        func scrollViewDidScroll(_ sv: UIScrollView) {
            let scrollable = max(sv.contentSize.height - sv.bounds.height, 1)
            parent.onScrollProgress(min(1, max(0, sv.contentOffset.y / scrollable)))
        }

        @objc func handleClosePan(_ g: UIPanGestureRecognizer) {
            let v = g.view
            let tx = g.translation(in: v).x
            switch g.state {
            case .began, .changed:
                parent.onCloseDragChanged(tx)
            case .ended, .cancelled, .failed:
                parent.onCloseDragEnded(tx, g.velocity(in: v).x)
            default:
                break
            }
        }

        // Only begin for a clearly-rightward horizontal drag → vertical reading wins.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let vel = pan.velocity(in: pan.view)
            return vel.x > 0 && abs(vel.x) > abs(vel.y) * 1.2
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - ReaderHTML (page assembly + house stylesheet)
enum ReaderHTML {

    /// Assemble the full reader page: house CSS + masthead (from card metadata) + body.
    static func page(for story: Story, safeTop: CGFloat, safeBottom: CGFloat) -> String {
        let body = story.bodyHTML ?? html(from: story.blocks)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>\(css(safeBottom: safeBottom))</style>
        </head>
        <body>
          <div class="hero"><img src="\(story.imageURL)" alt=""></div>
          <div class="masthead">
            <div class="eyebrow">\(esc(story.category))</div>
            <h1 class="title">\(esc(story.title))</h1>
            <div class="byline">
              <div class="chip">\(esc(story.mono))</div>
              <div class="who">
                <div class="author">\(esc(story.author))</div>
                <div class="meta">\(esc(story.source)) &middot; \(esc(story.date)) &middot; \(esc(story.readTime)) read</div>
              </div>
            </div>
          </div>
          <div class="rule"></div>
          <article class="body">\(body)</article>
        </body>
        </html>
        """
    }

    // MARK: House stylesheet — dark, Curio fonts, premium reading defaults.
    private static func css(safeBottom: CGFloat) -> String {
        """
        @font-face { font-family:'Schibsted'; src:url('SchibstedGrotesk-ExtraBold.ttf'); font-weight:800; font-display:swap; }
        @font-face { font-family:'Schibsted'; src:url('SchibstedGrotesk-Bold.ttf');      font-weight:700; font-display:swap; }
        @font-face { font-family:'Schibsted'; src:url('SchibstedGrotesk-SemiBold.ttf');  font-weight:600; font-display:swap; }
        @font-face { font-family:'Hanken'; src:url('HankenGrotesk-Regular.ttf');  font-weight:400; font-display:swap; }
        @font-face { font-family:'Hanken'; src:url('HankenGrotesk-Medium.ttf');   font-weight:500; font-display:swap; }
        @font-face { font-family:'Hanken'; src:url('HankenGrotesk-SemiBold.ttf'); font-weight:600; font-display:swap; }
        @font-face { font-family:'Hanken'; src:url('HankenGrotesk-Bold.ttf');     font-weight:700; font-display:swap; }

        :root {
          --bg:#08090B; --surface:#101216; --elevated:#1A1D23;
          --text:#F4F5F6; --sub:rgba(255,255,255,.62); --faint:rgba(255,255,255,.40);
          --line:rgba(255,255,255,.09); --accent:#6AA0FF;
          --sans:'Hanken',-apple-system,system-ui,sans-serif;
          --display:'Schibsted','Hanken',-apple-system,sans-serif;
          --mono:ui-monospace,'SF Mono',Menlo,monospace;
          --sb:\(Int(safeBottom))px;
        }
        * { margin:0; padding:0; box-sizing:border-box; -webkit-text-size-adjust:100%; }
        html,body { background:var(--bg); }
        body { font-family:var(--sans); color:var(--text); line-height:1.72;
               -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility; }
        img { max-width:100%; }

        .hero { position:relative; width:100%; height:42vh; background:var(--elevated); overflow:hidden; }
        .hero img { width:100%; height:100%; object-fit:cover; display:block; }
        .hero::after { content:''; position:absolute; inset:0; pointer-events:none;
          background:linear-gradient(to bottom, rgba(8,9,11,.42) 0, rgba(8,9,11,0) 20%,
                     rgba(8,9,11,0) 52%, var(--bg) 100%); }

        .masthead { padding:22px 22px 0; }
        .eyebrow { font-family:var(--mono); font-size:11px; font-weight:600; letter-spacing:.18em;
          color:var(--accent); text-transform:uppercase; }
        h1.title { font-family:var(--display); font-weight:800; font-size:32px; line-height:1.12;
          letter-spacing:-.02em; margin-top:12px; }
        .byline { display:flex; align-items:center; gap:11px; margin-top:18px; }
        .byline .chip { width:36px; height:36px; border-radius:9px; background:var(--elevated);
          display:flex; align-items:center; justify-content:center; font-weight:700; font-size:12.5px; }
        .byline .author { font-weight:600; font-size:14.5px; }
        .byline .meta { font-size:12.5px; color:var(--faint); margin-top:3px; }
        .rule { height:1px; background:var(--line); margin:20px 22px 0; }

        .body { padding:26px 22px calc(90px + var(--sb)); font-size:17.5px; }
        .body > * + * { margin-top:22px; }
        .body p { color:rgba(244,245,246,.92); line-height:1.75; }
        .body .lead { font-size:20px; font-weight:500; line-height:1.62; color:var(--text); }
        h2 { font-family:var(--display); font-weight:700; font-size:23px; line-height:1.25;
          letter-spacing:-.01em; margin-top:38px; }
        h3 { font-family:var(--display); font-weight:600; font-size:19px; margin-top:30px; }
        .body strong { font-weight:700; color:var(--text); }
        .body em { font-style:italic; }
        .body a { color:var(--accent); text-decoration:none; border-bottom:1px solid rgba(106,160,255,.35); }
        .body ul, .body ol { padding-left:22px; }
        .body li { margin-top:9px; line-height:1.68; color:rgba(244,245,246,.9); }
        .body li::marker { color:var(--accent); }

        blockquote { border-left:3px solid var(--accent); padding-left:18px; }
        blockquote p { font-family:var(--display); font-weight:600; font-size:21px; line-height:1.4; color:var(--text); }
        blockquote cite { display:block; margin-top:10px; font-family:var(--mono); font-size:10.5px;
          letter-spacing:.06em; color:var(--accent); font-style:normal; text-transform:uppercase; }

        figure { margin:0; }
        figure img { width:100%; border-radius:14px; border:1px solid var(--line); display:block; }
        figcaption { font-size:13px; color:var(--faint); font-style:italic; margin-top:10px; }

        table { width:100%; border-collapse:collapse; font-size:13.5px; border:1px solid var(--line);
          border-radius:14px; overflow:hidden; }
        thead { background:var(--elevated); }
        th,td { text-align:left; padding:11px 13px; border-bottom:1px solid var(--line); }
        th { font-weight:700; } td { color:var(--sub); }
        th:first-child, td:first-child { color:var(--text); }
        tr:last-child td { border-bottom:none; }

        pre { background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:16px;
          overflow-x:auto; font-family:var(--mono); font-size:13px; line-height:1.6; color:#c9d3e6; }
        p code, li code { background:var(--elevated); padding:2px 6px; border-radius:5px;
          font-family:var(--mono); font-size:.85em; color:#cdd6f4; }
        hr { border:none; height:1px; background:var(--line); margin:34px 0; }

        /* helper: callout box */
        .callout { background:var(--surface); border:1px solid var(--line); border-radius:14px; padding:18px 20px; }
        .callout > * + * { margin-top:10px; }
        .callout .k { font-family:var(--mono); font-size:11px; letter-spacing:.1em; color:var(--accent);
          text-transform:uppercase; }
        .callout ol, .callout ul { padding-left:20px; }
        /* helper: custom-visualization container (canvas / svg / bespoke widgets) */
        .viz { background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:20px; overflow:hidden; }
        .viz .cap { font-family:var(--mono); font-size:11px; letter-spacing:.08em; color:var(--faint);
          text-transform:uppercase; margin-top:14px; }
        """
    }

    // MARK: Fallback — render a story's `blocks` as house HTML when bodyHTML is nil.
    static func html(from blocks: [ArticleBlock]) -> String {
        blocks.map { block in
            switch block {
            case .lead(let t):
                return "<p class=\"lead\">\(inline(t))</p>"
            case .heading(let t):
                return "<h2>\(esc(t))</h2>"
            case .paragraph(let t):
                return "<p>\(inline(t))</p>"
            case .quote(let t, let cite):
                let c = cite.map { "<cite>\(esc($0))</cite>" } ?? ""
                return "<blockquote><p>\(esc(t))</p>\(c)</blockquote>"
            case .image(let url, let caption):
                let cap = caption.map { "<figcaption>\(esc($0))</figcaption>" } ?? ""
                return "<figure><img src=\"\(url)\" alt=\"\">\(cap)</figure>"
            case .table(let head, let rows):
                let th = head.map { "<th>\(esc($0))</th>" }.joined()
                let body = rows.map { r in "<tr>" + r.map { "<td>\(esc($0))</td>" }.joined() + "</tr>" }.joined()
                return "<table><thead><tr>\(th)</tr></thead><tbody>\(body)</tbody></table>"
            case .diagram(let title, let steps):
                let head = title.map { "<div class=\"k\">\(esc($0))</div>" } ?? ""
                let items = steps.map { "<li>\(inline($0))</li>" }.joined()
                return "<div class=\"callout\">\(head)<ol>\(items)</ol></div>"
            }
        }.joined(separator: "\n")
    }

    // MARK: Text helpers
    /// HTML-escape plain text.
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Escape, then convert inline markdown (**bold**, *italic*, [link](url)) to HTML.
    static func inline(_ s: String) -> String {
        var out = esc(s)
        out = regexReplace(out, #"\[([^\]]+)\]\(([^)]+)\)"#, "<a href=\"$2\">$1</a>")
        out = regexReplace(out, #"\*\*([^*]+)\*\*"#, "<strong>$1</strong>")
        out = regexReplace(out, #"\*([^*]+)\*"#, "<em>$1</em>")
        return out
    }

    private static func regexReplace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }
}

// MARK: - Flagship reader content
// A fully-authored house-styled article that exercises every element in the
// toolbox — the reference example the authoring spec points to.
enum ReaderContent {
    // Rewritten from content/ros-explainer.html into the Curio house format.
    static let ros = #"""
    <p class="lead">Despite the name, ROS isn't an operating system. It never was. And once you see what it actually is, you understand why almost every research robot on the planet quietly runs on it.</p>

    <p>Say "operating system" and you picture Linux or Windows — the thing that owns the hardware. ROS owns nothing. It sits <em>on top</em> of Linux and pulls a sneakier trick: it lets a swarm of separate programs on one robot behave as if they were a single mind.</p>

    <p>Picture a robot not as one machine but as a room full of specialists. One program does nothing but read the LIDAR. Another only plans paths. Another just drives the motors. <strong>ROS is the language they gossip in</strong> — and the real magic is that none of them knows who the others are.</p>

    <h2>Nodes: one job, one process</h2>
    <p>Each specialist is a <strong>node</strong> — a running program with exactly one job. Read a sensor. Compute a path. Fire a motor command. Every node lives in its own process, so when one falls over, the rest keep humming along, none the wiser.</p>
    <p>How many are we talking about? On a real robot, <strong>twenty to fifty nodes</strong> run at once — camera driver, IMU, SLAM, obstacle detector, controller, logger, visualizer — a whole city of tiny programs, each minding its own business.</p>

    <div class="viz">
      <svg viewBox="0 0 320 170" width="100%" role="img" aria-label="Publish-subscribe message bus">
        <rect x="8" y="71" width="72" height="30" rx="6" fill="#1A1D23" stroke="rgba(255,255,255,.14)"/>
        <text x="44" y="90" fill="#F4F5F6" font-size="11" text-anchor="middle" font-family="monospace">LIDAR</text>
        <line x1="80" y1="86" x2="116" y2="86" stroke="#6AA0FF" stroke-width="2"/>
        <rect x="118" y="72" width="84" height="28" rx="14" fill="#6AA0FF"/>
        <text x="160" y="91" fill="#08090B" font-size="11" text-anchor="middle" font-family="monospace" font-weight="700">/scan</text>
        <line x1="202" y1="86" x2="240" y2="35" stroke="rgba(106,160,255,.5)" stroke-width="2"/>
        <line x1="202" y1="86" x2="240" y2="86" stroke="rgba(106,160,255,.5)" stroke-width="2"/>
        <line x1="202" y1="86" x2="240" y2="137" stroke="rgba(106,160,255,.5)" stroke-width="2"/>
        <rect x="242" y="21" width="70" height="28" rx="6" fill="#1A1D23" stroke="rgba(255,255,255,.14)"/>
        <text x="277" y="39" fill="#F4F5F6" font-size="10" text-anchor="middle" font-family="monospace">SLAM</text>
        <rect x="242" y="72" width="70" height="28" rx="6" fill="#1A1D23" stroke="rgba(255,255,255,.14)"/>
        <text x="277" y="90" fill="#F4F5F6" font-size="10" text-anchor="middle" font-family="monospace">planner</text>
        <rect x="242" y="123" width="70" height="28" rx="6" fill="#1A1D23" stroke="rgba(255,255,255,.14)"/>
        <text x="277" y="141" fill="#F4F5F6" font-size="10" text-anchor="middle" font-family="monospace">logger</text>
      </svg>
      <div class="cap">One publisher, many subscribers — nobody knows who's listening</div>
    </div>

    <h2>Topics: fire and forget</h2>
    <p>Nodes never call each other directly. They <em>broadcast</em>. A node publishes messages onto a named channel — a <strong>topic</strong> — like a radio station firing into the air. Anyone tuned in receives it instantly. The station never checks who's listening; the listeners never learn who's transmitting. That deliberate ignorance is the whole point: it's what lets you rip out the path planner and bolt in a smarter one without touching another line of code.</p>
    <pre><code># the LIDAR node broadcasts raw scans
    pub = rospy.Publisher('/scan', LaserScan, queue_size=10)
    pub.publish(scan_msg)

    # the SLAM node just listens — its callback fires on every message
    rospy.Subscriber('/scan', LaserScan, slam_callback)</code></pre>

    <h2>Services: when you actually need an answer</h2>
    <p>Topics are perfect for firehoses — sensor readings and velocity commands streaming forever. But sometimes a node needs to <em>ask a question</em> and wait for the reply: "Is there an obstacle at X?" "Save this map." That's a <strong>service</strong> — a client sends a request, the server answers, the client waits.</p>
    <pre><code>rospy.wait_for_service('/check_obstacle')
    check = rospy.ServiceProxy('/check_obstacle', CheckObstacle)
    result = check(x=1.5, y=2.0)   # blocks until the answer comes back</code></pre>

    <h2>rosmaster: the matchmaker that vanishes</h2>
    <p>So how do a publisher and a subscriber ever find each other if neither knows the other exists? A hidden registry called <strong>rosmaster</strong>. When a node boots, it tells rosmaster what it publishes and what it wants. When two nodes turn out to care about the same topic, rosmaster introduces them — and then, crucially, gets out of the way. From that moment the messages flow node to node, peer to peer.</p>
    <blockquote>
      <p>rosmaster doesn't relay messages. It's a phonebook, not a post office.</p>
    </blockquote>

    <h2>ROS 1 vs ROS 2: the quiet revolution</h2>
    <p>The original design had one fatal flaw: a single rosmaster that, if it died, took the whole robot down with it. ROS 2 threw it out entirely and swapped in <strong>DDS</strong> — an industrial real-time standard — so nodes discover each other with no central point of failure. That one change turned ROS from a research toy into something you can actually ship.</p>
    <table>
      <thead><tr><th>&nbsp;</th><th>ROS 1</th><th>ROS 2</th></tr></thead>
      <tbody>
        <tr><td>Discovery</td><td>Central rosmaster</td><td>Peer-to-peer DDS</td></tr>
        <tr><td>Transport</td><td>TCP</td><td>Real-time DDS</td></tr>
        <tr><td>Multi-robot</td><td>Bolted on</td><td>Native</td></tr>
        <tr><td>Best for</td><td>Prototyping</td><td>Production fleets</td></tr>
        <tr><td>Status</td><td>EOL 2025</td><td>The future</td></tr>
      </tbody>
    </table>

    <div class="callout">
      <div class="k">The mental model</div>
      <p>ROS is a publish-subscribe message bus for robot programs. Each program is a node. Nodes broadcast onto named topics; others subscribe and react. Services handle the questions that need answers. rosmaster — or DDS in ROS 2 — runs the introductions. Every piece is swappable without disturbing the rest, and <em>that</em> modularity is why, when a new robot boots up in a lab tonight, the odds are overwhelming that ROS is already running inside it.</p>
    </div>
    """#

    // Rewritten from content/okf-reader.html
    static let okf = #"""
    <p class="lead">Foundation models can write code, summarize a document, and analyze a dataset in seconds. Ask one how your company computes "weekly active users," though, and it goes quiet — because the answer isn't in the model. It's scattered across six systems that were never built to talk to each other.</p>

    <p>That gap — between a capable model and the messy, specific knowledge an organization actually runs on — is the real bottleneck for enterprise AI in 2026. Google's proposed fix is almost cheeky in its simplicity. Not a platform. Not an API. A <strong>folder of markdown files</strong>.</p>

    <h2>The knowledge is everywhere, and nowhere</h2>
    <p>When an agent needs to answer a real question, it has to stitch the answer together from surfaces that all speak different languages:</p>
    <ul>
      <li><strong>Metadata catalogs</strong> — each with its own SDK, knowledge locked behind an API.</li>
      <li><strong>Wikis and drives</strong> — Confluence, Notion, Drive: human-readable, barely machine-readable.</li>
      <li><strong>Code comments</strong> — buried in repos, no standard shape, no way to discover them.</li>
      <li><strong>Senior engineers' heads</strong> — the most accurate source, and the least accessible.</li>
    </ul>
    <p>So every agent builder re-solves the same context problem from scratch, and every vendor reinvents the same data model. OKF's answer is to stop building services and agree on a <em>format</em>.</p>

    <h2>The pattern nobody named</h2>
    <blockquote>
      <p>LLMs don't get bored, don't forget to update a cross-reference, and can touch 15 files in one pass. The bookkeeping that causes humans to abandon personal wikis is exactly what LLMs are good at.</p>
      <cite>Andrej Karpathy</cite>
    </blockquote>
    <p>Teams building agents kept independently arriving at the same trick: give the agent a shared markdown library it can read and update. Obsidian vaults wired to coding agents, <code>AGENTS.md</code> and <code>CLAUDE.md</code> files, repos full of <code>index.md</code>. The pattern was everywhere — but every version was bespoke, and none could talk to another. OKF just standardizes the handful of conventions needed to make them interoperate.</p>

    <h2>A directory that becomes a graph</h2>
    <p>An OKF bundle is a directory. Each file is one concept — a table, a metric, a runbook. The file path is its identity; markdown links between files are the edges.</p>
    <pre><code>sales/
    ├── index.md            ← bundle root
    ├── tables/
    │   ├── orders.md
    │   └── customers.md    ← linked via markdown
    └── metrics/
        └── weekly_active_users.md</code></pre>
    <p>Each concept file carries a small block of YAML frontmatter for the fields that must be queryable, and a markdown body for everything else:</p>
    <pre><code>---
    type: BigQuery Table
    title: Orders
    tags: [sales, revenue]
    ---
    # Joins
    Joined with [customers](/tables/customers.md) on customer_id.</code></pre>
    <p>That last link isn't a comment — it's a typed, traversable edge. "Join this table on <code>customer_id</code>" becomes something an agent can <em>walk</em>, not just read.</p>

    <h2>Three rules that keep it from becoming another silo</h2>
    <div class="callout">
      <div class="k">Design principles</div>
      <ol>
        <li><strong>Minimally opinionated</strong> — the only required field is <code>type</code>. Everything else is up to the producer.</li>
        <li><strong>Producer/consumer independence</strong> — a human can author a bundle an agent consumes; one model can write what another queries.</li>
        <li><strong>Format, not platform</strong> — no cloud, no account, no SDK, ever. A knowledge format's value comes from how many parties speak it, not who owns it.</li>
      </ol>
    </div>

    <p>The full v0.1 spec fits on a single page — by design. A bundle ships as a tarball, lives in any git repo, renders on GitHub, and diffs cleanly in a pull request. The bet underneath it is easy to underestimate: the fix for fragmented AI context isn't a smarter platform you have to onboard into — it's a format so trivial to produce and consume that the ecosystem adopts it without asking permission.</p>
    """#

    // Rewritten from content/logto-reader.html
    static let logto = #"""
    <p class="lead">Every SaaS app needs the exact same things: users sign in, accounts stay secure, enterprise customers bring their own identity provider, and different people get different permissions. None of it is novel. All of it takes months to build correctly — and each piece has a CVE waiting if you get it wrong.</p>

    <p>Logto is the open-source escape hatch: a certified OpenID Connect provider you drop in front of your app to get sign-in, social login, passkeys, MFA, enterprise SSO, and role-based access — built <em>on</em> the standards instead of around them.</p>

    <h2>Build it yourself, or don't</h2>
    <p>Rolling your own auth means owning sessions, password hashing, token issuance, refresh-token rotation, PKCE, TOTP, and SAML SSO flows — each one a rabbit hole, each one a place to leak credentials. Logto ships all of it already implemented, audited, and spec-compliant. You configure it, call the SDK, and validate a JWT. Your app gets to stay in the business of being your app.</p>

    <h2>The clean split at its core</h2>
    <p>Logto is built on OIDC sitting on top of OAuth 2.1, and the division of labor is crisp:</p>
    <ul>
      <li><strong>OAuth 2.1 — authorization.</strong> Issues scoped, expiring access tokens that prove a client may call an API. Your API validates the token; no round-trip to Logto needed.</li>
      <li><strong>OIDC — authentication.</strong> Issues an ID token: a signed JWT of verified claims (email, name, <code>sub</code>) so your app knows <em>who</em> just logged in.</li>
    </ul>
    <p>It runs exactly one end-user flow — Authorization Code with PKCE, the modern standard. No implicit flow, no password grant; OAuth 2.1 deprecated those for good reason.</p>

    <h2>Tenants as first-class citizens</h2>
    <p>Most auth systems make you build "organizations" yourself. Logto models them natively — a user can belong to many orgs, hold a different role in each, and receive org-scoped tokens. Sign in with a company email and Logto routes you to that company's Okta or Azure AD automatically, with no code change on your side.</p>
    <pre><code>const token = await logto.getAccessToken({
      resource: 'https://api.yourapp.com',
      organizationId: 'org_abc123',
    });
    // JWT: { sub, aud, scope: 'manage:members view:analytics', org_id }</code></pre>

    <h2>Auth for agents, too</h2>
    <p>The timely part: Logto now treats AI agents as what they are — OAuth clients with unusual trust requirements. Via <strong>Token Exchange</strong> (RFC 8693), an agent can swap a user's token for one scoped only to what the agent needs, not everything the user can do. Least privilege, applied to autonomous software.</p>

    <div class="callout">
      <div class="k">The core idea</div>
      <p>A JWT access token is an audienced, scoped, signed <em>capability</em>. Logto's whole job is to issue the right token, with the right scopes, for the right resource, in the right org — and yours is simply to validate it. At 12k GitHub stars and v1.40, it's well past experiment and into serious-infrastructure territory.</p>
    </div>
    """#

    // Rewritten from content/ai-berkshire-reader.html
    static let aiBerkshire = #"""
    <p class="lead">Ask any chatbot to analyze a stock and you'll get a polished, balanced, thoughtful essay that ends with "investors should conduct their own due diligence" — in other words, useless for making a decision. One developer decided the problem wasn't the AI. It was the lack of discipline.</p>

    <p>AI Berkshire is a set of Claude Code commands that turn a single investor into a research firm. Each one runs a four-master methodology — Buffett, Munger, Duan Yongping, and Li Lu — as four independent agents that search, score, and <em>argue</em> before a team lead forces an actual conclusion. Not "balanced analysis." A buy, a pass, or an honest grey zone, with price targets.</p>

    <blockquote>
      <p>Price is what you pay, value is what you get.</p>
      <cite>Warren Buffett</cite>
    </blockquote>

    <h2>Four masters, designed to disagree</h2>
    <p>The trick is that the four lenses aren't complements — they're built to collide. Buffett says "cheap." Li Lu says "not certain enough." Duan asks "is this even a good business?" Munger asks "how does it die?" That tension is what produces a usable answer instead of a shrug.</p>
    <ul>
      <li><strong>Duan Yongping — business essence.</strong> Is this a good business at all, before any numbers?</li>
      <li><strong>Warren Buffett — moat + valuation.</strong> Durable advantage, then price below intrinsic value.</li>
      <li><strong>Charlie Munger — inversion.</strong> Forces failure scenarios <em>before</em> success ones, and checks the AI's own biases.</li>
      <li><strong>Li Lu — the long arc.</strong> Is this business still here in ten years? Often the tie-breaker.</li>
    </ul>

    <h2>Four agents, running at once</h2>
    <p>Crucially, <code>/investment-team</code> doesn't split one prompt into four sections — it spawns four fully independent agents, each with its own web access and its own conclusion, which may contradict the others. Four times the search volume, four verdicts to reconcile. And because LLMs can't do arithmetic, every number that matters runs through a Python module using exact decimal math — market-cap checks, cross-source validation, even a Benford's-Law fraud sniff test.</p>

    <h2>The uncomfortable part</h2>
    <p>The project leads not with a backtest but with a screenshot of a real brokerage account — two years of live trading:</p>
    <table>
      <thead><tr><th>Strategy</th><th>2024</th><th>2025 YTD</th></tr></thead>
      <tbody>
        <tr><td>AI Berkshire (live)</td><td>+69.3%</td><td>+66.4%</td></tr>
        <tr><td>S&amp;P 500</td><td>+23.3%</td><td>+16.4%</td></tr>
        <tr><td>Nasdaq</td><td>+28.6%</td><td>+20.4%</td></tr>
        <tr><td>CSI 300</td><td>+14.7%</td><td>+17.7%</td></tr>
      </tbody>
    </table>

    <div class="callout">
      <div class="k">The real bet</div>
      <p>The bottleneck in investment research was never access to information — any investor can read an annual report. It's the discipline to process it the same way every time. The value here isn't the AI; it's the structured methodology the AI is forced to follow. Two years of beating every major benchmark isn't proof it always works — but it's unusually honest evidence that, so far, it has. <em>Not investment advice.</em></p>
    </div>
    """#

    // Rewritten from content/openpilot-reader.html
    static let openpilot = #"""
    <p class="lead">For $299 and a plug behind your rear-view mirror, openpilot quietly hijacks your car's own steering and cruise-control wiring and hands the driving to a neural network. Its latest release did something stranger still: it learned to drive entirely inside a simulation that taught <em>itself</em> the laws of physics from dashcam video.</p>

    <p>First, the important caveat: this is not a self-driving car. It's a Level 2 co-pilot — the same category as Tesla Autopilot — that keeps your hands on the wheel and watches your eyes with an inward camera. Step on the brake and you're instantly back in control. What it replaces is the <em>brain</em> behind your car's factory cruise and lane-centering, with a model trained on millions of miles of real driving.</p>

    <h2>It speaks your car's own language</h2>
    <p>Modern cars run a <strong>CAN bus</strong> — the wire network connecting engine, brakes, steering, and cameras. Your factory driver-assist already sends commands over it; openpilot simply intercepts that bus and sends better ones, through the same connector the OEM cameras use. From the car's point of view, it just looks like a smarter version of what it already had.</p>
    <p>The safety story is architectural, not just procedural. A separate microcontroller called <strong>panda</strong> — dumb, dedicated, written in review-hardened C — enforces hard limits on every command before it reaches the bus. Even if the neural network goes rogue, panda won't pass a dangerous signal. It doesn't trust the model.</p>

    <h2>A robot trained inside a dream</h2>
    <p>The March 2026 release, 0.11, is the milestone. Earlier versions trained the driver against a hand-coded simulator — which could only fake small steering nudges, and which the network learned to <em>cheat</em> by exploiting rendering artifacts that don't exist in reality. Adding more rules just made it brittle.</p>
    <p>So comma replaced the simulator with a <strong>World Model</strong>: a 2-billion-parameter network that watched 2.5 million minutes of driving and learned to predict what the camera sees next, given an action. The training loop became almost poetic:</p>
    <ol>
      <li>Train the World Model to dream realistic driving video from raw fleet footage — no human labels.</li>
      <li>Train a <em>smaller</em> driving policy by letting it act inside that dream and improve.</li>
    </ol>
    <p>The key insight: because the policy is smaller than the world it plays in, it can't memorize its way to cheating — and unlike a hand-coded simulator, this one just gets better with more data. comma says it's the first real-world robot shipped to users that was trained entirely this way.</p>

    <div class="callout">
      <div class="k">Why it matters past your commute</div>
      <p>Train a policy inside a learned simulation, then deploy it into reality — that template applies to any robot where real data is cheap but hand-coded physics is brittle: warehouse arms, drones, inspection bots. openpilot is a consumer product quietly funding a frontier robotics lab, and it just open-sourced the lab's latest output to the 61,000 people watching on GitHub.</p>
    </div>
    """#

    // Rewritten from content/physisforcing-reader.html
    static let physisforcing = #"""
    <p class="lead">The best video models can now generate footage of a robot arm picking up an apple that looks completely real — until you step through it frame by frame and watch the apple drift sideways in mid-air, the gripper teleport, and a pushed box refuse to move. The video isn't ugly. It's <em>impossible</em>.</p>

    <p>That matters more than it sounds. When these videos are used as a "world model" to train robot policies, physically wrong predictions teach the robot the wrong lessons about what actions are even possible. A new paper from Peking University and NVIDIA, <strong>PhysisForcing</strong>, fixes it — not with more data or a bigger model, but by teaching the model exactly <em>where</em> physics lives.</p>

    <h2>Two ways to break reality</h2>
    <ul>
      <li><strong>Local — trajectory discontinuity.</strong> The gripper jumps between frames; contact forces blink in and out. Motion isn't smooth.</li>
      <li><strong>Global — relational inconsistency.</strong> A grasped object drifts away from the hand; a pushed object stays put. Geometry looks fine locally, but the <em>causality</em> between objects is wrong.</li>
    </ul>

    <h2>Why ordinary fine-tuning fails</h2>
    <p>Standard training treats every pixel equally — the blank wall, the static floor, and the one tiny contact zone where the actual physics is happening all get the same weight. The signal that matters is diluted to near-zero before it can steer anything. PhysisForcing's insight: physical evidence is <em>spatially concentrated</em>. So first, find those regions — using a point tracker and a depth estimator to flag pixels that both move a lot and sit in the foreground — then supervise only there.</p>

    <h2>Two losses, two levels</h2>
    <p>With the physics-critical mask in hand, it applies two complementary losses that stack because they fix different errors:</p>
    <ol>
      <li><strong>Pixel-level</strong> — aligns per-point motion inside the mask, steering the transformer's internal features to track real point trajectories.</li>
      <li><strong>Semantic-level</strong> — uses a frozen video encoder as a "physics teacher," matching which regions relate to which, so grasped objects stay coupled to the gripper.</li>
    </ol>
    <p>Both are thrown away at inference — <strong>zero extra cost at deployment</strong>.</p>

    <table>
      <thead><tr><th>Model</th><th>Overall</th><th>Manipulation</th></tr></thead>
      <tbody>
        <tr><td>Wan2.2 (base)</td><td>50.7</td><td>38.1</td></tr>
        <tr><td>Wan2.2 (fine-tuned)</td><td>57.9</td><td>52.3</td></tr>
        <tr><td>PhysisForcing</td><td>63.8</td><td>58.9</td></tr>
      </tbody>
    </table>

    <div class="callout">
      <div class="k">The broader lesson</div>
      <p>Physical correctness turned out to be functional, not cosmetic: better rollouts lifted closed-loop planning from 16% to 24% success. When a generative model fails on a structured constraint, the right fix often isn't more scale — it's supervision aimed precisely at where the constraint actually lives.</p>
    </div>
    """#

    // Rewritten from content/rcclx-reader.html
    static let rcclx = #"""
    <p class="lead">Everyone obsesses over how fast AI chips are. The quieter truth: when you run a large model across dozens of GPUs, up to 30% of the time is spent not computing — just waiting for the chips to talk to each other. Meta went hunting for that lost time on AMD hardware and clawed back a double-digit chunk of it.</p>

    <p>The result is <strong>RCCLX</strong>, an open-source upgrade to AMD's GPU communication library with two ideas that need no changes to the model code you already run.</p>

    <h2>Why the chatter costs so much</h2>
    <p>Splitting a model across GPUs means they constantly swap partial results — "collective" operations like <code>AllReduce</code>. During <strong>decode</strong> (generating tokens one at a time), the work is memory-bound and this synchronization hits hardest: every token you see waits on it. Shave that latency and every word in a chat response arrives sooner.</p>

    <h2>Idea 1: stop passing the bucket</h2>
    <p>Classic AllReduce sends data around a ring of GPUs, so latency grows with the number of chips — <code>O(N)</code>. Meta's <strong>Direct Data Access</strong> lets each GPU read every other GPU's memory directly and reduce locally, collapsing that to roughly <code>O(1)</code>. It moves more total data, but far fewer synchronization rounds.</p>
    <ul>
      <li>10–50% faster AllReduce for small messages (the decode phase)</li>
      <li>10–30% faster for the larger messages of prefill</li>
      <li>~10% cut in time-to-incremental-token — the delay between words appearing</li>
    </ul>

    <h2>Idea 2: compress before you ship it</h2>
    <p>The second trick is almost cheeky: why send 32-bit floats across the interconnect when 8-bit will do? Low-precision collectives quantize the <em>wire transfer</em> to FP8 — up to 4:1 compression — while keeping the actual math in full precision. The accuracy cost on a standard reasoning benchmark was about 0.3%; functionally invisible.</p>
    <pre><code>import torchcomms
    comm = torchcomms.new_comm("rcclx", torch.device("hip"), name="my_comm")
    comm.allreduce(t, torchcomms.ReduceOp.SUM, async_op=False)
    # the only AMD-specific parts are "rcclx" and "hip"</code></pre>
    <p>To turn on the compression, you set one environment variable. No code changes.</p>

    <div class="callout">
      <div class="k">The bigger story</div>
      <p>This is really about vendor diversification: hyperscalers no longer build for NVIDIA alone, and running production AI on AMD demands software <em>parity</em>, not just hardware. RCCLX's two durable ideas — skip the ring when you can read memory directly, and compress before you transmit — buy a ~10% latency win from smarter use of the wires between chips, not faster chips. As AMD scales up, those software wins compound.</p>
    </div>
    """#
}

#Preview {
    DetailView(story: sampleStories[0],
               onCloseDragChanged: { _ in },
               onCloseDragEnded: { _, _ in },
               onClose: {})
        .environment(\.theme, .dark)
        .environment(\.safeTop, 59)
        .environment(\.safeBottom, 34)
        .preferredColorScheme(.dark)
}
