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

        // WKWebView can otherwise restore a prior scroll position for the same
        // baseURL — every story should open at the top.
        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            web.scrollView.setContentOffset(.zero, animated: false)
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
          <script>\(highlightScript)</script>
        </body>
        </html>
        """
    }

    // MARK: Tiny inline syntax highlighter — VSCode Dark+-style tokens for
    // <pre><code> blocks (comments, strings, numbers, keywords, slash-commands).
    // Not a full tokenizer, just enough to make code read as code, not gray text.
    private static let highlightScript = #"""
    document.querySelectorAll('pre code').forEach(function (block) {
      var text = block.textContent
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      var re = /(#[^\n]*)|('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")|(\b\d+(?:\.\d+)?\b)|(\b(?:def|class|import|from|return|if|elif|else|for|while|in|as|with|try|except|finally|raise|yield|lambda|None|True|False|and|or|not|is|const|let|var|function|await|async|new|export|struct|func|guard)\b)|(\/[a-zA-Z][\w-]*)/g;
      block.innerHTML = text.replace(re, function (m, c, s, n, k, f) {
        if (c) return '<span class="tok-c">' + c + '</span>';
        if (s) return '<span class="tok-s">' + s + '</span>';
        if (n) return '<span class="tok-n">' + n + '</span>';
        if (k) return '<span class="tok-k">' + k + '</span>';
        if (f) return '<span class="tok-f">' + f + '</span>';
        return m;
      });
    });
    """#

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
        body { font-family:var(--sans); color:var(--text); line-height:1.62;
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
        h1.title { font-family:var(--display); font-weight:800; font-size:26px; line-height:1.16;
          letter-spacing:-.02em; margin-top:12px; }
        .byline { display:flex; align-items:center; gap:11px; margin-top:18px; }
        .byline .chip { width:36px; height:36px; border-radius:9px; background:var(--elevated);
          display:flex; align-items:center; justify-content:center; font-weight:700; font-size:12.5px; }
        .byline .author { font-weight:600; font-size:13.5px; }
        .byline .meta { font-size:12px; color:var(--faint); margin-top:3px; }
        .rule { height:1px; background:var(--line); margin:20px 22px 0; }

        .body { padding:26px 22px calc(90px + var(--sb)); font-size:15px; }
        .body > * + * { margin-top:20px; }
        .body p { color:rgba(244,245,246,.92); line-height:1.65; }
        .body .lead { font-size:17px; font-weight:500; line-height:1.55; color:var(--text); }
        h2 { font-family:var(--display); font-weight:700; font-size:19px; line-height:1.25;
          letter-spacing:-.01em; margin-top:34px; }
        h3 { font-family:var(--display); font-weight:600; font-size:16.5px; margin-top:26px; }
        .body strong { font-weight:700; color:var(--text); }
        .body em { font-style:italic; }
        .body a { color:var(--accent); text-decoration:none; border-bottom:1px solid rgba(106,160,255,.35); }
        .body ul, .body ol { padding-left:22px; }
        .body li { margin-top:8px; line-height:1.6; color:rgba(244,245,246,.9); }
        .body li::marker { color:var(--accent); }

        blockquote { border-left:3px solid var(--accent); padding-left:18px; }
        blockquote p { font-family:var(--display); font-weight:600; font-size:15px; line-height:1.45; color:var(--text); }
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
        /* VSCode Dark+-inspired token colors, applied by the tiny highlighter below */
        .tok-c { color:#6A9955; font-style:italic; }
        .tok-s { color:#CE9178; }
        .tok-n { color:#B5CEA8; }
        .tok-k { color:#C586C0; }
        .tok-f { color:#4FC1FF; }
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
    // Rewritten from content/*.html — kept close to each source's own title
    // and wording; restructured into the Curio house HTML/CSS toolkit only.
    static let ros = #"""
    <p class="lead">Despite the name, ROS isn't an operating system like Linux or Windows. It's middleware, a layer that sits on top of Linux and lets separate programs running on a robot talk to each other as if they were one system.</p>

    <p>Think of a robot as a collection of specialists: one program reads the LIDAR sensor, another runs the path planner, another drives the motors. ROS is the protocol that lets them exchange data in real time, without any of them needing to know who the others are.</p>

    <h2>Nodes: one job, one process</h2>
    <p>A node is just a running program. Each node does one thing: read a sensor, compute a path, send a motor command. They run independently. If one crashes, the others keep going.</p>
    <p>On a real robot you might have 20 to 50 nodes active simultaneously: camera driver, IMU driver, SLAM node, obstacle detector, controller, logger, visualizer.</p>

    <h2>Topics: a one-way broadcast channel</h2>
    <p>Nodes communicate by publishing and subscribing to topics, named channels that carry a specific message type. A publisher fires data into the topic; any subscriber instantly receives it. Publishers don't know who's listening. Subscribers don't know who's sending. This loose coupling is what makes ROS systems modular.</p>
    <ul>
      <li><strong>Publisher</strong> &mdash; broadcasts on a topic continuously, like a radio station. Doesn't wait for receivers. Fires and forgets.</li>
      <li><strong>Subscriber</strong> &mdash; listens to a topic and calls a callback function every time a message arrives. Can subscribe to many topics at once.</li>
    </ul>
    <pre><code># LIDAR node publishes raw scan data
        pub = rospy.Publisher('/scan', LaserScan, queue_size=10)
        pub.publish(scan_msg)

        # SLAM node subscribes: callback fires on each message
        rospy.Subscriber('/scan', LaserScan, slam_callback)</code></pre>

    <h2>Services: ask a question, wait for the answer</h2>
    <p>Topics are great for streams: sensor readings, camera frames, velocity commands. But sometimes you need a direct question and answer: "Is there an obstacle at coordinate X?" or "Save this map." That's what services are for. A client sends a request; the server blocks and returns a response.</p>
    <pre><code># Client calls a service and waits
        rospy.wait_for_service('/check_obstacle')
        check = rospy.ServiceProxy('/check_obstacle', CheckObstacle)
        result = check(x=1.5, y=2.0)  # blocks until response</code></pre>

    <h2>rosmaster: the matchmaker that stays invisible</h2>
    <p>When a node starts, it registers with rosmaster, a central registry that knows which nodes exist and which topics they publish or subscribe to. When a publisher and subscriber both declare interest in the same topic, rosmaster introduces them and then steps out of the way. After that, messages flow directly between nodes, peer to peer.</p>
    <blockquote><p>rosmaster doesn't relay messages. It's a phonebook, not a post office.</p></blockquote>

    <h2>ROS 1 vs ROS 2: what changed</h2>
    <p>ROS 2 dropped rosmaster entirely. Instead of a central registry, nodes use DDS (Data Distribution Service), an industry standard for real-time peer-to-peer communication. This makes ROS 2 suitable for production systems: multi-robot fleets, real-time control, systems without a master node that can fail.</p>
    <table>
    <thead><tr><th></th><th>ROS 1</th><th>ROS 2</th></tr></thead>
    <tbody>
    <tr><td>Discovery</td><td>Central rosmaster</td><td>DDS, no master</td></tr>
    <tr><td>Transport</td><td>TCP-based</td><td>Real-time DDS</td></tr>
    <tr><td>Best for</td><td>Research, rapid prototyping</td><td>Multi-robot, production</td></tr>
    <tr><td>Status</td><td>EOL in 2025</td><td>Actively developed</td></tr>
    </tbody>
    </table>

    <div class="callout">
    <div class="k">The mental model</div>
    <p>ROS is a publish-subscribe message bus for robot programs. Each program is a node. Nodes broadcast data onto named topics. Other nodes subscribe and react. Services handle synchronous requests. rosmaster (ROS 1) or DDS (ROS 2) handles discovery. The whole system is designed so you can swap any one piece, change the path planner, upgrade the sensor driver, without touching anything else. That modularity is why virtually every research robot in the world runs ROS.</p>
    </div>
    """#

    static let okf = #"""
    <p class="lead">OKF (Open Knowledge Format) is an open spec for representing the context AI agents need, table schemas, metric definitions, join paths, runbooks, as a directory of markdown files with YAML frontmatter. No SDK. No cloud account. No runtime. Just files that humans can read and agents can traverse. The goal: make organisational knowledge as portable as JSON, so any agent from any vendor can consume it without translation.</p>

    <h2>The problem: every organisation's knowledge lives in six incompatible places</h2>
    <p>Foundation models can write code, summarise documents, and analyse datasets, but only when they have the right context. And in most organisations, that context is scattered across systems that were never designed to talk to each other.</p>
    <p>When an AI agent needs to answer "How do I compute weekly active users from our event stream?" it has to assemble the answer from these scattered, mutually incompatible surfaces:</p>
    <ul>
      <li><strong>Metadata catalogs</strong> &mdash; each with their own API, their own SDK, knowledge locked inside.</li>
      <li><strong>Wikis and shared drives</strong> &mdash; Confluence, Notion, Google Drive, non-portable, hard to parse programmatically.</li>
      <li><strong>Code comments and docstrings</strong> &mdash; buried in repos, no standard shape, no discovery mechanism.</li>
      <li><strong>Senior engineers' heads</strong> &mdash; the most accurate source, the least accessible one.</li>
    </ul>
    <p>The result: every agent builder solves the same context-assembly problem from scratch. Every catalog vendor reinvents the same data models. The knowledge stays locked behind whichever surface created it. OKF's answer is not another service, it's a format.</p>

    <h2>The pattern it formalises: knowledge as a living wiki</h2>
    <blockquote>
    <p>LLMs don't get bored, don't forget to update a cross-reference, and can touch 15 files in one pass. The bookkeeping that causes humans to abandon personal wikis is exactly what LLMs are good at.</p>
    <cite>Andrej Karpathy, LLM Wiki gist</cite>
    </blockquote>
    <p>Developer teams building AI agents had independently arrived at the same pattern: give the agent a shared markdown library it can read and update. The pattern kept reappearing under different names, Obsidian vaults wired to coding agents, AGENTS.md and CLAUDE.md convention files, repos full of index.md and log.md artifacts, and "metadata as code" repositories inside data teams.</p>
    <p>The pattern is compelling. But each instance is bespoke. None of these wikis were designed to cooperate: no agreed-upon field names, no agreed-upon filenames, no way to pipe one team's knowledge catalog into another team's agent. OKF formalises the small set of conventions needed to make the pattern interoperable.</p>

    <h2>How it works: a directory of markdown files that becomes a knowledge graph</h2>
    <p>An OKF bundle is a directory. Each file is a concept, anything you want to capture: a table, a dataset, a metric, a runbook, an API. The file path is the concept's identity. Markdown links between files create the graph.</p>
    <pre><code>sales/
        &#9500;&#9472;&#9472; index.md            &lt;- bundle root
        &#9500;&#9472;&#9472; datasets/
        &#9474;   &#9500;&#9472;&#9472; index.md
        &#9474;   &#9492;&#9472;&#9472; orders_db.md    &lt;- one concept per file
        &#9500;&#9472;&#9472; tables/
        &#9474;   &#9500;&#9472;&#9472; index.md
        &#9474;   &#9500;&#9472;&#9472; orders.md
        &#9474;   &#9492;&#9472;&#9472; customers.md    &lt;- linked via markdown
        &#9492;&#9472;&#9472; metrics/
            &#9500;&#9472;&#9472; index.md
            &#9492;&#9472;&#9472; weekly_active_users.md</code></pre>
    <p>Each concept file has a small YAML frontmatter block for the structured fields that need to be queryable, and a markdown body for everything else:</p>
    <pre><code>---
        type: BigQuery Table
        title: Orders
        description: One row per completed customer order.
        resource: https://console.cloud.google.com/bigquery?p=acme&amp;d=sales&amp;t=orders
        tags: [sales, revenue]
        timestamp: 2026-05-28T14:30:00Z
        ---
        # Schema
        | Column | Type | Description |
        |--------|------|-------------|
        | order_id | STRING | Globally unique order identifier. |
        | customer_id | STRING | FK to [customers](/tables/customers.md). |

        # Joins
        Joined with [customers](/tables/customers.md) on `customer_id`.</code></pre>
    <p>Markdown links between concept files turn the directory into a graph richer than the parent/child hierarchy implied by the filesystem. The graph is the value: "join this table on customer_id" is now a typed, traversable edge, not a comment buried in a docstring.</p>

    <h2>Design philosophy: three principles that keep it from becoming another proprietary standard</h2>
    <div class="callout">
    <div class="k">P1 &mdash; Minimally opinionated</div>
    <p>OKF requires exactly one thing of every concept: a type field. What types exist, what other fields to include, what sections the body has, left to the producer. The spec defines the interoperability surface, not the content model.</p>
    </div>
    <div class="callout">
    <div class="k">P2 &mdash; Producer/consumer independence</div>
    <p>A bundle hand-authored by a human can be consumed by an AI agent. A bundle generated by a metadata export pipeline can be browsed in a visualizer. A bundle synthesised by one LLM can be queried by another. The format is the contract; tooling at each end is independently swappable.</p>
    </div>
    <div class="callout">
    <div class="k">P3 &mdash; Format, not platform</div>
    <p>OKF is not tied to any cloud, database, model provider, or agent framework. It will never require a proprietary account or SDK to read, write, or serve. The value of a knowledge format comes from how many parties speak it, not from who owns it.</p>
    </div>
    <p>The full v0.1 specification, conformance criteria, cross-linking rules, and reserved filenames, fits on a single page. A bundle is shippable as a tarball, hostable in any git repo, mountable on any filesystem. Readable in any editor. Renderable on GitHub. Indexable by any search tool.</p>

    <h2>Reference implementations: three things shipped to make the format concrete</h2>
    <ul>
      <li><strong>Producer, BigQuery enrichment agent.</strong> Walks a BigQuery dataset, drafts an OKF concept document for every table and view, then runs a second LLM pass that crawls authoritative docs and enriches each concept with citations, schemas, and join paths.</li>
      <li><strong>Consumer, static HTML visualizer.</strong> Turns any OKF bundle into an interactive graph view in a single self-contained HTML file. No backend, no install on the viewing side, no data leaves the page.</li>
      <li><strong>Sample bundles</strong> &mdash; GA4 e-commerce (Google Analytics public dataset), Stack Overflow (BigQuery public dataset), and Bitcoin on-chain data, all committed to the repo as living, conformant examples.</li>
    </ul>
    <p>These are deliberately proofs of concept. The agent demonstrates one way to produce OKF; the visualizer demonstrates one way to consume it. The ecosystem of producers and consumers is expected to grow far beyond what Google has shipped. Google Cloud's Knowledge Catalog has also been updated to ingest OKF bundles and serve them to agents, but the format itself works entirely independently of that product.</p>

    <h2>Why it matters: the missing layer between AI agents and organisational knowledge</h2>
    <p>The bottleneck for enterprise AI in 2026 is not model capability, it's context. Models are capable. What they lack is access to the specific, current, accurate knowledge that makes a general answer into a useful one: the join path between two tables, the business definition of a metric, the deprecation notice for an API endpoint that went offline in March.</p>
    <p>Today, that knowledge either doesn't exist in a form agents can consume, or exists in forms siloed behind proprietary catalog APIs that require specific SDKs, specific cloud accounts, and specific integrations. Every agent builder re-solves the same problem. Every vendor re-invents the same data models.</p>
    <p><strong>For data teams,</strong> it means documentation as code: OKF bundles live in version control alongside the schemas they describe. They diff cleanly. They get reviewed in pull requests. They inherit all the tooling that makes code maintainable, and agents handle the bookkeeping that makes wikis die.</p>
    <p><strong>For agent builders,</strong> it means context without integration: an agent that can traverse an OKF bundle gets table schemas, join paths, metric definitions, and related concept links without a catalog API key, without an SDK, and without being locked into a specific vendor's knowledge graph format.</p>

    <div class="callout">
    <div class="k">Key takeaway</div>
    <p>OKF makes a bet that's easy to underestimate: the right answer to fragmented AI context is a format, not a platform. Markdown plus YAML frontmatter plus a few file conventions is all it takes to make organisational knowledge portable across agents, vendors, and teams. The full-page spec, the zero-SDK requirement, the git-native file structure: these aren't limitations, they're the point. A format that's trivial to produce and trivial to consume will get adopted; a platform that requires onboarding won't. OKF is also an honest acknowledgement that the LLM-wiki pattern developers have been independently discovering for a year deserves a stable, interoperable shape, and that the best way to establish that shape is to publish it openly and let the ecosystem build the tooling.</p>
    </div>
    """#

    static let logto = #"""
    <p class="lead">Logto is an open-source alternative to Auth0 and Cognito, built on OIDC and OAuth 2.1. Drop it in front of your app and you get a full sign-in UI, social login, passkeys, MFA, enterprise SSO, role-based access control, and multi-tenant organization management, all configurable through a console or API, with SDKs for 30+ frameworks.</p>

    <h2>Why it exists: auth is a solved problem nobody wants to solve</h2>
    <p>Every SaaS app needs the same things: users can sign in, accounts are secure, enterprise customers can use their own identity provider (Okta, Azure AD), and different users have different permissions. These are not novel problems.</p>
    <p>But implementing them correctly, on top of OIDC, OAuth 2.1, SAML, JWT validation, refresh token rotation, PKCE, and a dozen other specs, takes months. Commercial solutions like Auth0 and Cognito solve this but are expensive and opaque. Logto is the open-source, self-hostable answer, built on the same standards.</p>
    <p>Rolling your own means owning sessions, password hashing, token issuance, refresh rotation, PKCE, MFA TOTP, SSO SAML flows, JIT provisioning. Each one is a rabbit hole. Each one has a CVE waiting if you get it wrong. Logto ships all of it already implemented, audited, and spec-compliant. You configure it, call its SDK, validate JWTs. Your app stays in the business of being your app.</p>

    <h2>The foundation: built on OIDC and OAuth 2.1</h2>
    <p>Logto's core is a certified OpenID Connect provider (OIDC), built on the node-oidc-provider library. Every auth flow it runs is a standards-compliant OIDC/OAuth 2.1 flow, meaning any client library in any language already knows how to talk to it.</p>
    <p>OIDC sits on top of OAuth 2.1 and adds one thing: a standardized way to get verified identity claims (who is this user?) alongside an access token (what can they do?). The split is clean:</p>
    <ul>
      <li><strong>OAuth 2.1, authorization.</strong> Issues access tokens that prove a client is allowed to call an API. Scoped, expiring, audience-bound. Your API validates the token, no round-trip to Logto needed.</li>
      <li><strong>OIDC, authentication.</strong> Issues an ID token, a JWT containing verified user claims (email, name, sub). Your app reads this to know who is logged in.</li>
    </ul>
    <p>The flow it runs for end-users is the Authorization Code Flow with PKCE, the standard used by every web and mobile app. No implicit flow, no password grant, OAuth 2.1 deprecates those for good reason. It also supports OIDC Discovery, PKCE (RFC 7636), Token Introspection, Token Revocation, Resource Indicators (RFC 8707), Token Exchange (RFC 8693), Back-Channel Logout, and SAML 2.0.</p>

    <h2>Architecture: three APIs, one monolith, one database</h2>
    <p>Logto's backend is a single Node.js service (@logto/core) backed by PostgreSQL. It exposes three distinct API surfaces, each serving a different consumer:</p>
    <ul>
      <li><strong>OIDC Provider, /oidc.</strong> The standards-compliant OIDC server. Your apps' login flows point here. Issues authorization codes, ID tokens, access tokens, refresh tokens.</li>
      <li><strong>Management API, /api.</strong> Full REST API for managing users, organizations, roles, permissions, connectors, and every Logto resource programmatically. Admin-role only.</li>
      <li><strong>Account API, /api/my.</strong> End users access their own profile directly, update email, phone, MFA, social connections, without routing through the Management API.</li>
    </ul>
    <p>One Docker Compose command starts Logto and PostgreSQL:</p>
    <pre><code># Spin up in 30 seconds
        curl -fsSL https://raw.githubusercontent.com/logto-io/logto/HEAD/docker-compose.yml \
          | docker compose -p logto -f - up

        # Your OIDC discovery endpoint is now live at:
        # http://localhost:3001/oidc/.well-known/openid-configuration</code></pre>

    <h2>End-user flows: sign-in is a hosted UI you configure, not build</h2>
    <p>Logto ships a complete, customizable sign-in UI. You configure what auth methods appear; Logto renders and handles the flow. Your app just redirects to Logto and receives a token back. No signup form to build. No password reset email to wire up.</p>
    <ul>
      <li><strong>Identity methods.</strong> Email + password, phone + SMS OTP, magic link, passkey (WebAuthn), social login (Google, GitHub, Apple, Facebook, Okta, Azure AD, 50+ connectors). All toggle-able per app.</li>
      <li><strong>Security layers.</strong> TOTP authenticator apps, SMS 2FA, backup codes. Plus CAPTCHA, identifier lockout, email/phone blocklist, password policy enforcement.</li>
      <li><strong>Enterprise SSO.</strong> For B2B SaaS: configure OIDC or SAML connections per customer domain. When a user signs in with a company email, Logto automatically routes them to that company's identity provider, without any code changes in your app.</li>
    </ul>

    <h2>Multi-tenancy: organizations as first-class objects</h2>
    <p>Most auth systems treat "organizations" (workspaces, tenants) as something you build on top. Logto models them natively. Each user can belong to multiple organizations, have different roles in each, and get org-scoped access tokens.</p>
    <ul>
      <li><strong>Organization template.</strong> Define once, apply everywhere. Roles and permissions defined in the template apply to every organization. Change the template and all orgs inherit it.</li>
      <li><strong>JIT provisioning.</strong> Users signing in via a company SSO domain are automatically added to the right organization with the right role, no admin invite needed.</li>
    </ul>

    <h2>Authorization: RBAC, two levels, three models</h2>
    <p>Logto's RBAC operates at two levels: global (across your whole tenant) and organization (within a specific org). When a user requests an access token, they specify a resource (a URI identifying the API) and optionally an organization context. Logto issues a JWT containing the exact scopes that user's role grants for that resource in that org. Your API validates the JWT, no Logto round-trip at request time.</p>
    <pre><code>// Requesting an org-scoped access token (React SDK)
        const token = await logto.getAccessToken({
          resource: 'https://api.yourapp.com',
          organizationId: 'org_abc123',
        });

        // JWT payload includes:
        // { sub, iss, aud, scope: 'manage:members view:analytics', org_id: 'org_abc123' }</code></pre>

    <h2>What's new: auth for AI agents and MCP</h2>
    <p>Logto explicitly supports Model Context Protocol (MCP) and agent-based AI architectures. It ships a hosted MCP server that connects AI tools and IDEs to Logto Cloud for managing resources. For M2M (machine-to-machine) scenarios, AI agents calling APIs on behalf of users, it supports OAuth 2.1 Token Exchange, letting an agent swap a user token for a narrowly-scoped downstream token.</p>
    <p>This matters because AI agents are just OAuth clients with unusual trust requirements. Logto already has the primitives, scoped tokens, RBAC, org context, that agent authorization needs.</p>
    <div class="callout">
    <div class="k">Token Exchange (RFC 8693)</div>
    <p>An AI agent presents a user's token and exchanges it for a token scoped only to what the agent needs to do, not everything the user can do. The principle of least privilege, applied to agents.</p>
    </div>

    <div class="callout">
    <div class="k">Key takeaway</div>
    <p>Logto is what auth infrastructure looks like when you start from the standards, OIDC, OAuth 2.1, RFC 8707, and build upward, rather than working around them. The core insight: a JWT access token is an audienced, scoped, signed capability. Logto's job is to issue the right token with the right scopes for the right resource in the right org, and yours is to validate it. Everything else, the sign-in UI, the SSO connectors, the organization model, the RBAC system, exists to make sure that token is correct. At 12k stars and v1.40, it's well past the "interesting experiment" stage and into "serious infrastructure" territory.</p>
    </div>
    """#

    static let aiBerkshire = #"""
    <blockquote>
    <p>Price is what you pay, value is what you get. Ordinary people ask AI for analysis that looks right. AI Berkshire produces research reports you can actually make decisions from.</p>
    <cite>Warren Buffett (original) &middot; ai-berkshire README (application)</cite>
    </blockquote>

    <p class="lead">AI Berkshire is a collection of Claude Code slash-commands that turn a single investor into a research firm. Each command runs the four-master methodology, Buffett's moats, Munger's inversion, Duan Yongping's business essence, Li Lu's civilisational arc, as four parallel AI agents that independently search, analyse, and challenge each other before a Team Lead synthesises a forced-conclusion report. Not "balanced analysis." Actual buy/pass/grey-zone decisions with price targets.</p>

    <h2>Why it exists: the problem with asking AI to analyse a stock</h2>
    <p>You can ask any LLM to analyse Pinduoduo. You'll receive a polished piece covering growth potential, competitive risks, regulatory concerns, and valuation, balanced, thoughtful, and completely useless for making a decision. It ends with "investors should conduct their own due diligence."</p>
    <p>AI Berkshire solves a different problem: not whether AI can analyse, but whether the analysis has enough structure, rigour, and discipline to replace the cognitive functions of a professional research team.</p>
    <div class="callout">
    <div class="k">Generic chatbot</div>
    <p>"Pinduoduo shows strong growth potential with its C2M model, but faces increasing competition from ByteDance and regulatory uncertainty. Investors should weigh these factors carefully..."</p>
    </div>
    <div class="callout">
    <div class="k">AI Berkshire &mdash; /investment-team</div>
    <table>
    <thead><tr><th>Strategy</th><th>Recommendation</th><th>Price</th></tr></thead>
    <tbody>
    <tr><td>Aggressive</td><td>Build 20% position</td><td>$95&ndash;105</td></tr>
    <tr><td>Balanced</td><td>Wait for buyback clarity</td><td>$85&ndash;95</td></tr>
    <tr><td>Conservative</td><td>Pass, 10yr uncertainty</td><td>&mdash;</td></tr>
    </tbody>
    </table>
    <p>Mirror test: can't explain in 5 sentences = don't buy. No exceptions.</p>
    </div>

    <h2>The methodology: four masters, designed to disagree</h2>
    <p>The core insight of AI Berkshire is that the four masters are not complements, they're designed to create genuine tension. Buffett says "cheap." Li Lu says "not certain enough." Duan says "good business." Munger asks "how does it die?" That collision is what generates useful analysis.</p>
    <ul>
      <li><strong>Duan Yongping, business essence.</strong> Is this a good business in the first place? C2M model, network effects, pricing power. Scores the nature of the business before any numbers.</li>
      <li><strong>Warren Buffett, moat + valuation.</strong> Network effects, switching costs, scale. Then: is price below intrinsic value? FCF yield, reverse DCF, three-scenario targets.</li>
      <li><strong>Charlie Munger, inversion + bias check.</strong> "How does this company die?" Forces failure scenarios before success scenarios. Checks AI-specific biases: recency, narrative, English-language source skew.</li>
      <li><strong>Li Lu, civilisational arc.</strong> Does this business align with long-term civilisational progress? Is it still here in 10 years? The most demanding filter, often the tie-breaker.</li>
    </ul>
    <blockquote>
    <p>Buffett: "Cash-adjusted PE of 6.3x, this is a cash machine. Score 4.4/5." Li Lu: "Management culture has hidden risks. 10-year certainty is insufficient. Score 2.0/5."</p>
    <cite>Real tension, Pinduoduo example &middot; result: grey zone, not a pass, not a fail</cite>
    </blockquote>

    <h2>The engine: four agents running simultaneously, not sequentially</h2>
    <p>The key architectural distinction: /investment-team doesn't split one prompt into four sections. It spawns four fully independent Claude Code agents, each with its own search quota, its own web access, and its own conclusion, which may contradict the others. A Team Lead then synthesises, noting where agents disagreed. Four times the search volume. Four times the independent data sources. Four verdicts that must be reconciled.</p>
    <pre><code># Spawn 4 parallel research agents on Meituan
        /investment-team Meituan

        # Each agent independently runs web searches, cross-validates data,
        # and produces a scored analysis. Team Lead reconciles conflicts.
        # Output: composite score, 3-strategy recommendation, price targets</code></pre>

    <h2>Financial rigour: LLMs cannot do arithmetic</h2>
    <p>A PE ratio miscalculated by a decimal point, or a market cap confused between HKD and CNY, produces a wrong investment thesis. AI Berkshire's financial_rigor.py handles every calculation that matters, using Python's decimal.Decimal, not floating point.</p>
    <ul>
      <li><strong>Market Cap Verify.</strong> Price &times; shares, compared against the reported figure. Flags currency unit mismatches, a real case caught a Tencent HKD vs CNY billion discrepancy.</li>
      <li><strong>Cross-Validation.</strong> Every key metric must come from two or more independent sources. A discrepancy above 1% triggers an alert and forces reconciliation before the report proceeds.</li>
      <li><strong>Three-Scenario DCF.</strong> Bull, base, and bear valuations with exact decimal arithmetic. Reverse DCF: what growth rate does the current price imply?</li>
      <li><strong>Benford's Law.</strong> Checks financial data's first-digit distribution against Benford's Law. An anomalous distribution is a fraud signal, rare but important.</li>
    </ul>
    <pre><code># Market cap manual verification, Tencent example
        python3 tools/financial_rigor.py verify-market-cap \
          --price 510 --shares 9.11e9 \
          --reported 4.65e12 --currency HKD
        # Verified. Deviation: 0.08%</code></pre>

    <h2>Built-in anti-bias</h2>
    <p>The most dangerous AI output is one that looks right but isn't. AI Berkshire treats AI bias as a first-class problem, with five structural mechanisms:</p>
    <table>
    <thead><tr><th>Mechanism</th><th>Problem it solves</th></tr></thead>
    <tbody>
    <tr><td>Information richness rating (A/B/C)</td><td>Prevents "more data = more certainty" illusion</td></tr>
    <tr><td>Munger inversion check</td><td>Forces failure scenarios before success</td></tr>
    <tr><td>8-point veto list</td><td>One red flag = instant rejection regardless of valuation</td></tr>
    <tr><td>Anti-consensus check</td><td>Avoids groupthink with market consensus</td></tr>
    <tr><td>Blank principle</td><td>Prefers "I don't know" over false certainty</td></tr>
    </tbody>
    </table>

    <h2>The toolkit: 16 skills, from a 10-minute screen to a 120,000-word series</h2>
    <p>The commands span five categories: deep research (/investment-team, /investment-research, /management-deep-dive, /private-company-research, /deep-company-series), earnings (/earnings-review, /earnings-team), screening (/industry-research, /industry-funnel, /quality-screen, /investment-checklist), portfolio (/portfolio-review, /thesis-tracker, /news-pulse), and thinking (/dyp-ask, /financial-data).</p>

    <h2>The track record: real money, real years, real screenshots</h2>
    <p>The README leads with a screenshot from a real Futu Securities account, not a backtested simulation:</p>
    <table>
    <thead><tr><th>Index / Strategy</th><th>2024</th><th>2025 YTD</th></tr></thead>
    <tbody>
    <tr><td>AI Berkshire (live)</td><td>+69.29%</td><td>+66.38%</td></tr>
    <tr><td>S&amp;P 500</td><td>+23.31%</td><td>+16.39%</td></tr>
    <tr><td>Hang Seng Index</td><td>+17.67%</td><td>+27.77%</td></tr>
    <tr><td>Nasdaq</td><td>+28.64%</td><td>+20.36%</td></tr>
    <tr><td>CSI 300</td><td>+14.68%</td><td>+17.66%</td></tr>
    </tbody>
    </table>
    <p><em>Disclaimer, from the README: historical returns do not represent future performance. Screenshots are from a real Futu Securities account. This framework is for learning and research only, not investment advice. Always do your own due diligence.</em></p>

    <div class="callout">
    <div class="k">Key takeaway</div>
    <p>AI Berkshire is a bet on a specific thesis: the bottleneck in investment research is not access to information, it's the discipline to process it consistently. Any investor can read an annual report. Few can run four independent analytical frameworks on it simultaneously, force a conclusion, verify every number with cross-source validation, and do it in 30 minutes for seven companies in parallel. The framework's value isn't the AI, it's the structured methodology the AI is constrained to follow. That the two-year live track record substantially outperforms all major benchmarks isn't proof the approach always works, but it's unusually honest evidence that it has so far.</p>
    </div>
    """#

    static let openpilot = #"""
    <p class="lead">openpilot is open-source software that hijacks your car's existing driver-assistance electronics and replaces the decision-making with a neural network, giving you significantly better adaptive cruise control and lane centering on 300+ production cars, all from a $299 plug-in device. Its latest release ships the first real-world robot agent trained entirely inside a learned simulation, a breakthrough a decade in the making.</p>

    <h2>01 &mdash; What it is: not a self-driving car, a smarter co-pilot</h2>
    <p>openpilot is a Level 2 driver assistance system, the same category as Tesla Autopilot or GM Super Cruise. It keeps your hands on the wheel and your eyes on the road. What it does is replace the brain behind your car's built-in adaptive cruise control (ACC) and lane centering with a neural network trained on millions of miles of real driving data.</p>
    <p>The result: smoother acceleration and braking, better lane centering, and a forward collision warning system that's meaningfully more capable than what your car shipped with. It also adds a camera-based driver monitoring system that watches for distraction or drowsiness.</p>
    <ul>
      <li><strong>ACC, Adaptive Cruise Control.</strong> Replaces your car's speed and following behavior with a neural net that accelerates and brakes more smoothly than factory tuning.</li>
      <li><strong>ALC, Automated Lane Centering.</strong> Steers to keep you centered in your lane. The model doesn't rely on painted lane lines, it learned a world model of road geometry.</li>
      <li><strong>FCW, Forward Collision Warning.</strong> Vision-based alert system that fires earlier and more reliably than most OEM implementations.</li>
      <li><strong>DM, Driver Monitoring.</strong> Inward-facing camera watches your eyes and head pose. Alerts if you're distracted or falling asleep. Engagement is mandatory for openpilot to stay on.</li>
    </ul>
    <div class="callout">
    <div class="k">Important distinction</div>
    <p>openpilot is not autonomy. The driver must remain alert and able to retake control at any moment. The system is specifically designed to fail gracefully, step on the brake and you're back in control instantly.</p>
    </div>

    <h2>02 &mdash; How it works: it speaks your car's own language</h2>
    <p>Most modern cars have a CAN bus, a communication backbone that connects every electronic module: the engine, brakes, steering, cameras, radar. Your factory ADAS system already sends control commands over this bus. openpilot intercepts that bus and sends better ones.</p>
    <p>It doesn't rewire anything fundamental. It plugs into your car's existing harness connector, the same port used by the OEM cameras and radar, via a car harness and a small device called the comma four. From the car's perspective, it just looks like a smarter version of the system it already had.</p>
    <ul>
      <li><strong>Neural network driving policy.</strong> Takes camera frames as input, outputs steering angle, acceleration, and braking commands. As of 0.11, fully trained end-to-end inside a learned simulator (World Model).</li>
      <li><strong>openpilot OS</strong> (selfdrived, plannerd, controlsd). Linux-based processes handling sensor fusion, path planning, actuator limits, and safety checks. Written in Python and C++.</li>
      <li><strong>panda, safety co-processor.</strong> A dedicated STM32 microcontroller that enforces hard limits on every command before it touches the CAN bus, written in C with MISRA compliance. Even if the Python layer goes rogue, panda won't send dangerous signals.</li>
      <li><strong>opendbc, car fingerprinting database.</strong> A community-built database of CAN message definitions for 300+ cars. This is how openpilot knows how to "speak" each car's protocol.</li>
    </ul>

    <h2>03 &mdash; The big leap, openpilot 0.11: the first real-world robot trained inside a dream</h2>
    <p>The March 2026 release of openpilot 0.11 is the most significant release in the project's history. The headline: the driving policy is now trained entirely inside a learned neural network simulator, a World Model, with no hand-coded physics or geometry rules. comma claims this is the first real-world robotics agent shipped to real users that was fully trained this way.</p>
    <p>comma described this vision in a 2016 paper titled "Learning a Driving Simulator." In 2021, they shipped end-to-end models. In 2023, commaVQ produced their first transformer-based world model. 0.11 is where these threads converge: the world model generates training data, the policy trains only on that data, both improve together.</p>
    <p>Previous releases trained the driving model using a classical, hand-coded simulator, a reprojection engine that could only realistically simulate small lateral deviations. It couldn't generate convincing examples of slowing down from highway speed or merging, so the model never reliably learned those behaviors. A bigger problem: neural networks are clever. They learn to exploit simulator artifacts, patterns that exist in the simulation but not in reality. The only fix was to add more hand-coded rules, which made the simulator more brittle, not better.</p>
    <p>A World Model is a neural network that learns to predict the future: given a sequence of frames and an action (steer left, brake), it generates what the camera would see next. Instead of physics rules, it learned world dynamics directly from 2.5 million minutes of real driving video. The new training loop works in two steps:</p>
    <ol>
      <li><strong>Train the World Model.</strong> A large 2B-parameter diffusion transformer learns to generate realistic driving video given context frames and actions. Trained on unlabeled fleet data, no human labelers needed.</li>
      <li><strong>Train the driving policy.</strong> A small transformer interacts with the World Model, taking actions, getting simulated video back, getting better. Like a video game AI training against a photorealistic simulator, except the simulator itself learned from reality.</li>
    </ol>
    <p>The key insight: as long as the driving policy is smaller than the World Model, it can't "cheat" by exploiting simulator artifacts, there are too many possibilities to memorize. And unlike hand-coded simulators, a learned one gets better simply by training on more data. The result is a model that converges to sensible highway speeds, handles parked cars more reactively, and has driven users to prefer Experimental mode (the full end-to-end policy) over the traditional ACC policy.</p>

    <h2>04 &mdash; The hardware: comma four, a $299 device that does a lot</h2>
    <p>openpilot runs on the comma four, comma's purpose-built device. It's roughly phone-sized and mounts behind your rearview mirror. It has its own cameras (road-facing and driver-facing), a Snapdragon SoC, and the panda co-processor built in. The 0.11 release also cut the device's idle power draw (when parked, waiting for ignition) by 77%.</p>
    <table>
    <thead><tr><th>State</th><th>Power</th></tr></thead>
    <tbody>
    <tr><td>Typical car (key-off)</td><td>250&ndash;600 mW</td></tr>
    <tr><td>+ comma four (pre-0.11)</td><td>225 mW</td></tr>
    <tr><td>+ comma four (0.11)</td><td>52 mW</td></tr>
    <tr><td>BMW diagnostic threshold</td><td>600 mW</td></tr>
    </tbody>
    </table>
    <p>This was achieved in three stages: disabling unused peripherals on the STM32 microcontroller, dropping voltage scaling from VOS1 to VOS3, and entering deep "stop mode" where the CPU halts entirely, woken only by CAN signals or hardware ignition detection. Practically: at 225 mW, the device could drain a car battery in weeks of inactivity. At 52 mW, it's months.</p>

    <h2>05 &mdash; Safety model: two rules that can never be overridden</h2>
    <p>openpilot follows ISO 26262 (automotive functional safety standard) and FMVSS requirements for Level 2 systems. Safety-critical code runs through MISRA C:2012 guidelines. But the most important safety properties are architectural, not just process-level.</p>
    <ol>
      <li>The driver must always be able to immediately retake control, by stepping on the brake or pressing cancel. openpilot disengages instantly. No override, no delay.</li>
      <li>The car must not change trajectory faster than a human can react. The panda co-processor enforces hard actuator limits, steering angle, lateral acceleration, braking force, before any command hits the CAN bus. The neural network cannot exceed these limits even if it tries.</li>
    </ol>
    <p>The second rule is where panda matters most. It's a separate microcontroller running C code reviewed to MISRA standards. It can't be patched by the Python layer. It doesn't trust the neural network. Every single CAN command goes through panda's safety checks, always.</p>
    <p>openpilot is MIT licensed and actively forked, but comma enforces meaningful rules for forks: you cannot disable driver monitoring, cannot disable excessive actuation checks, and if you modify the safety code in opendbc, your fork loses the openpilot trademark and must preserve all safety tests. Violating these gets your users banned from comma's servers.</p>

    <h2>06 &mdash; Roadmap: what openpilot 1.0 looks like</h2>
    <p>The project's stated 1.0 goal is a fully end-to-end driving policy: one neural network making all driving decisions, from perceiving the world to actuating the car. In progress: end-to-end longitudinal control in Chill mode, driver monitoring with sleep detection, rolling CI-pushed updates, and panda safety 1.0. Already shipped in 0.11: full World Model driving for the lateral axis.</p>
    <p>The World Model approach is the key enabler here. Because improvement comes from scale (more data, bigger model) rather than hand-coded rules, the ceiling for driving quality is dramatically higher. comma's own data already shows that users on the nightly branch prefer the end-to-end Experimental mode over ACC, the model is winning on behavior, not just benchmarks.</p>

    <h2>07 &mdash; The bigger picture: why this project matters beyond your commute</h2>
    <p>openpilot is unusual in the autonomous vehicle space because it is genuinely open source, genuinely deployed, and genuinely improving. Most AV efforts are either closed-source moonshots or narrow geofenced robotaxis. openpilot runs on your Honda Civic, on public roads, right now, with 61,000 people watching the code on GitHub.</p>
    <p>The World Model approach in 0.11 has implications well beyond driving. Training a robotics policy entirely inside a learned simulation, then deploying it into the real world successfully, is a template that applies to any physical system where real-world data is cheap but hand-coded simulation is expensive or brittle: warehouse robots, drone navigation, industrial inspection.</p>
    <p>comma has also made an unusual strategic bet: their data flywheel comes from users who opt in to uploading driving data to help train better models. The more openpilot is used, the better it gets, the more it's used. It's a consumer product funding a frontier robotics research lab, and they just open-sourced the lab's latest output.</p>

    <div class="callout">
    <div class="k">Key takeaway</div>
    <p>openpilot is the most ambitious open-source robotics project most people haven't heard of. It intercepts your car's own CAN bus, replaces the decision-making with a neural network, and enforces safety through a dedicated hardware co-processor that the software layer cannot override. The 0.11 release marks a genuine methodological shift: the driving model now trains entirely inside a neural net that learned the physics of the world from driving video, sidestepping the brittleness of hand-coded simulation. The scaling law here is straightforward: more data, better world model, better driver, and comma is already seeing it in production usage patterns. This is what a decade-long compounding bet on open-source robotics looks like when it starts to pay off.</p>
    </div>
    """#

    static let physisforcing = #"""
    <p class="lead">Video models trained to generate robot manipulation footage still produce physically wrong motion: objects that float, grippers that tunnel through surfaces, grasped items that drift. PhysisForcing fixes this by adding two complementary training losses focused exclusively on physics-critical regions, one aligning per-point motion trajectories at the pixel level, one aligning robot-object interaction semantics at the semantic level. No extra inference cost. +22.3% on R-Bench; closed-loop planning success 16% to 24%.</p>

    <h2>The problem: video models know what robots look like, they don't know how physics works</h2>
    <p>Large video generation models, Sora, Wan, Cosmos, can produce visually convincing robot footage. The gripper looks right. The scene looks right. But play it back frame by frame and you'll find: the gripper teleports. A grasped apple drifts laterally for no reason. A pushed object stays still. The robot's arm deforms between frames.</p>
    <p>These aren't aesthetic problems. They're causal violations, the generated frames no longer describe a physically realizable sequence of events. That matters enormously when the video is being used as a world model for training robot policies, where physically wrong predictions mislead the downstream policy about what actions are possible.</p>
    <ul>
      <li><strong>Local failure mode, trajectory discontinuity.</strong> The gripper jumps between frames. Object positions don't evolve smoothly. Contact forces appear or disappear instantaneously. Standard reconstruction losses treat these the same as background pixels.</li>
      <li><strong>Global failure mode, relational inconsistency.</strong> A pushed object stays static. A grasped object drifts away from the gripper mid-air. The video doesn't violate geometry locally, it violates interaction causality globally. Harder to detect, harder to fix.</li>
    </ul>
    <p>Robot-specific finetuning with reconstruction objectives treats every pixel equally: the static background, the wall, and the gripper-object contact zone all get the same gradient weight. Physical information is concentrated in a tiny fraction of the scene. The supervision signal is diluted to near-zero before it can steer the model toward physical correctness.</p>

    <h2>The core insight: physics is hierarchical, and it's local</h2>
    <p>The paper's key observation: physical plausibility in manipulation has two distinct levels, and the evidence for both is spatially concentrated in a tiny fraction of the frame. The framework first identifies physics-informative regions using a point tracker and a depth estimator. The tracker extracts dense 2D trajectories across frames. Points with high motion magnitude and high foreground relevance (close to the camera, on the robot or object, not the background) are marked as physics-critical.</p>
    <pre><code>// Foreground-weighted physics score per tracked point:
        q_i = a_i * r_i
        // a_i = trajectory motion magnitude across frames
        // r_i = 1 / (depth + eps)  -- closer = more foreground
        // Points above mean score -> physics mask M_phy
        M_phy_i = 1 if q_i &gt;= mean(q_j for all j)</code></pre>
    <p>This mask is then used to gate both training losses, supervision is applied only where robot-object interactions are actually happening. Background pixels, static surfaces, and far objects are completely ignored during physics alignment.</p>

    <h2>Loss 1 of 2, pixel-level: trajectory alignment</h2>
    <p>Once the physics mask identifies where interactions are, the first loss ensures per-point motion continuity within those regions. It works by extracting intermediate DiT features, specifically from the middle transformer block, where motion and structure information is most informative, and treating them as a feature map from which point locations can be predicted.</p>
    <p>For each tracked point in frame 0, the method computes a similarity map between that point's feature and every spatial location in subsequent frames. The argmax of the softmax over this similarity map is the predicted location of the point at time t. This prediction is then compared against the ground-truth trajectory from CoTracker3.</p>
    <pre><code>// Similarity map for point i at time t:
        s_i_t(x) = Q(p0_i)^T . K_t(x) / sqrt(C)
        // Predicted location via coordinate expectation:
        p_hat_i_t = sum_x softmax(s_i_t(x)) * x
        // Masked trajectory loss (only physics-critical points):
        L_pix = (1/|M|) * || M . (P_pred - P_gt) ||^2</code></pre>
    <p>The key insight here: this loss operates on DiT latent features, not the decoded video pixels. It steers the internal representation of the diffusion transformer so that its learned motion representation stays consistent with trackable point trajectories, rather than just optimizing pixel-level appearance.</p>

    <h2>Loss 2 of 2, semantic-level: relational alignment</h2>
    <p>The pixel-level loss fixes local motion. But it can't enforce that a grasped object stays coupled with the gripper, or that a pushed object moves in the right direction. These are relational properties, they're about how different regions relate to each other through time.</p>
    <p>The semantic-level loss uses a frozen video understanding encoder (V-JEPA 2, trained by predicting masked spatio-temporal features rather than pixels) as a teacher. Its token-to-token similarity structure captures exactly the inter-region coupling that manipulation requires, because self-supervised video encoders implicitly learn object-centric relational representations.</p>
    <pre><code>// For each pair of physics-masked tokens i, j:
        R_hat(i,j) = cosine(DiT_token_i, DiT_token_j)    // student
        R(i,j)     = cosine(JEPA_token_i, JEPA_token_j)  // teacher
        // Align the KxK pairwise relation matrices:
        L_sem = (1/K^2) * sum_ij |R_hat(i,j) - R(i,j)|</code></pre>
    <p>Critically, the loss aligns similarity structure, not absolute features. This means the DiT doesn't need to produce the same features as V-JEPA 2, it just needs to agree on which tokens are related to which. The teacher is frozen and discarded at inference. Zero extra cost at deployment. Ablations show layer 15 of 25 is optimal for injecting this signal: early blocks carry shallow appearance features without semantic structure, late blocks are specialized for noise prediction and harder to steer.</p>

    <h2>Results: consistent gains across all benchmarks and backbone families</h2>
    <p>R-Bench evaluates across 9 sub-dimensions: 5 task types (manipulation, spatial, multi-entity, long-horizon, reasoning) and 4 embodiments (single-arm, dual-arm, quadruped, humanoid). PhysisForcing improves all of them.</p>
    <table>
    <thead><tr><th>Model</th><th>Overall</th><th>Manipulation</th><th>Long-horizon</th><th>Multi-entity</th></tr></thead>
    <tbody>
    <tr><td>Wan2.2-I2V-A14B (base)</td><td>50.7</td><td>38.1</td><td>50.1</td><td>37.3</td></tr>
    <tr><td>Wan2.2-I2V-A14B (ft)</td><td>57.9</td><td>52.3</td><td>54.5</td><td>45.2</td></tr>
    <tr><td>PF-Wan (ours)</td><td>62.0</td><td>56.4</td><td>58.4</td><td>49.1</td></tr>
    <tr><td>Cosmos3-Nano (base)</td><td>58.4</td><td>55.0</td><td>57.6</td><td>46.6</td></tr>
    <tr><td>Cosmos3-Nano (ft)</td><td>61.5</td><td>57.8</td><td>59.3</td><td>49.2</td></tr>
    <tr><td>PF-Cosmos (ours)</td><td>63.8</td><td>58.9</td><td>60.8</td><td>51.3</td></tr>
    <tr><td>Wan2.6 (commercial)</td><td>60.7</td><td>54.6</td><td>51.4</td><td>47.9</td></tr>
    <tr><td>Veo 3.1 (commercial)</td><td>59.9</td><td>54.1</td><td>59.2</td><td>53.4</td></tr>
    </tbody>
    </table>
    <p>PF-Cosmos achieves the best overall R-Bench score of any evaluated model, including commercial systems like Wan2.6, Veo 3.1, and Seedance 1.5 Pro, and robotics-specific models like Cosmos3-Super and Abot-PhysWorld.</p>
    <p>On Wan2.2-TI2V-5B, each loss individually helps; combined is best. The pixel loss gives the larger single-loss gain (it fixes trajectory discontinuity, the most common failure). The semantic loss repairs global relational errors. They target different error modes and stack additively: vanilla finetune scores 44.8, pixel-only 47.2, semantic-only 46.2, both combined 47.5.</p>

    <h2>Beyond generation: physically correct videos make better robot policies</h2>
    <p>The paper tests a crucial hypothesis: if physically aligned video models are better world simulators, they should produce stronger representations for downstream robot learning.</p>
    <ul>
      <li><strong>WorldArena, action planner.</strong> Under WorldArena's protocol, the video model acts as an action planner, predicting future frames which are decoded into actions and executed in a simulator. PhysisForcing lifts closed-loop planning success from 16.0% to 24.0%, surpassing all world-model planner baselines including WoW (20.5%).</li>
      <li><strong>RoboTwin 2.0, policy learning.</strong> When PhysisForcing-trained Wan2.2-TI2V-5B replaces the base video DiT in Fast-WAM, average policy success improves from 68.2% to 72.8%. Largest gains on contact-rich tasks: place_empty_cup +21.5pp, press_stapler +11pp.</li>
    </ul>
    <p>The key implication: physical plausibility is not just an aesthetic property of generated video, it is a functional one. A world model that generates physically correct rollouts provides a better learning signal for policies that need to reason about contact, force, and object interaction.</p>

    <div class="callout">
    <div class="k">Key takeaway</div>
    <p>PhysisForcing makes a clean argument: the reason video models generate physically wrong robot manipulation is that existing training objectives are spatially indiscriminate. Physics happens in specific places, around grippers, contact zones, and moving objects, and standard reconstruction losses dilute that signal across the entire frame. The fix is to identify those regions dynamically, then apply two complementary losses that operate at different levels of abstraction: trajectory continuity at the pixel level, interaction semantics at the relational level. The framework adds no inference cost, works across model families and scales (Wan2.2 at 5B and 14B, Cosmos3-Nano at 16B), and produces gains that flow downstream into actual robot policy success, not just benchmark numbers. The broader lesson: when a generative model fails on a structured constraint, the right intervention is often not more data or a bigger model, but supervision that is geometrically and semantically focused on where the constraint actually lives.</p>
    </div>
    """#

    static let rcclx = #"""
    <p class="lead">Meta open-sourced RCCLX, a fork of AMD's GPU communication library (RCCL) with two major upgrades: a smarter memory-access algorithm (DDA) and a compression trick for collective operations (Low Precision). Together they make large language models run noticeably faster on AMD MI300X hardware, without changing the code your models already use.</p>

    <h2>01 &mdash; Background: why GPU communication is the bottleneck nobody talks about</h2>
    <p>Training and serving large AI models requires dozens, sometimes thousands, of GPUs working in sync. Each GPU handles a slice of the model, but they constantly need to share partial results. That data exchange is called a collective communication operation (think AllReduce, AllGather, ReduceScatter).</p>
    <p>The problem: these collectives can eat up to 30% of total inference time. On NVIDIA hardware, Meta already had a custom library (NCCLX) to address this. On AMD hardware, they relied on AMD's stock RCCL library, which left a lot of performance on the table. RCCLX is Meta's answer: an enhanced, open-sourced version of RCCL, fully integrated into Torchcomms, their unified PyTorch API so the same code works across GPU vendors.</p>

    <h2>02 &mdash; First principles: the two phases of running a language model</h2>
    <p>To understand why the fixes matter, you need to know how LLM inference actually works.</p>
    <ul>
      <li><strong>Prefill.</strong> Processes your entire input prompt at once, building a "KV cache" for each layer. This is compute-bound, the GPU's math units are the limiting factor. Attention cost scales quadratically with prompt length.</li>
      <li><strong>Decode.</strong> Generates tokens one by one, using and updating the KV cache. This is memory-bound, time is dominated by reading model weights and cache from GPU memory. Communication latency hits hardest here.</li>
    </ul>
    <p>With tensor parallelism, one model is split across multiple GPUs. After each layer, they must synchronize, that's where AllReduce lives, and why shaving its latency directly speeds up every token you generate.</p>

    <h2>03 &mdash; Feature 1: Direct Data Access (DDA), cutting AllReduce from O(N) to O(1)</h2>
    <p>Standard ring-based AllReduce sends data around a "ring" of GPUs. Each GPU passes messages to its neighbor, so latency grows with the number of GPUs: O(N). DDA breaks that scaling.</p>
    <ul>
      <li><strong>DDA Flat Algorithm</strong> (for small messages). Each GPU directly reads memory from all other GPUs and does a local reduction. Instead of passing a bucket around the ring, every GPU grabs what it needs directly. Latency becomes O(1), at the cost of more total data movement (O(n&sup2;) instead of O(n)).</li>
      <li><strong>DDA Tree Algorithm</strong> (for slightly larger messages). Splits AllReduce into two stages (reduce-scatter and all-gather), using direct memory access in each. Moves the same total data as a ring but collapses multiple synchronization rounds into a constant factor.</li>
    </ul>
    <p>Results on AMD MI300X GPUs vs. the RCCL baseline: 10 to 50% faster AllReduce for small messages (decode phase), 10 to 30% faster for larger messages (prefill phase), and a roughly 10% reduction in time-to-incremental-token (TTIT), the latency between each word appearing in a chat response. A 10% cut there is directly felt by users.</p>

    <h2>04 &mdash; Feature 2: Low-Precision Collectives, compress data, then communicate</h2>
    <p>The second big idea is simpler in concept: why send 32-bit floats when you can send 8-bit ones? Low Precision (LP) collectives compress tensor data before transmitting it across the interconnect, then decompress on the other side. Specifically, they quantize FP32 or BF16 data to FP8, giving up to a 4:1 compression ratio. Computation still happens in FP32 to preserve numerical accuracy, only the wire transfer is compressed.</p>
    <p>This exploits AMD's Infinity Fabric (the high-bandwidth GPU interconnect) efficiently by reducing the bytes that need to cross it, which matters most for large message sizes of 16MB or more.</p>
    <table>
    <thead><tr><th>Metric</th><th>Change</th><th>Note</th></tr></thead>
    <tbody>
    <tr><td>Latency</td><td>&darr; ~9&ndash;10%</td><td>Faster responses</td></tr>
    <tr><td>Throughput</td><td>&uarr; ~7%</td><td>More requests/sec</td></tr>
    <tr><td>GSM8K accuracy</td><td>~0.3% delta</td><td>Precision loss is negligible</td></tr>
    </tbody>
    </table>
    <p>GSM8K is a standard math reasoning benchmark. A 0.3% accuracy delta means the model's outputs are functionally unchanged, the quantization doesn't meaningfully hurt quality. To enable it: just set RCCL_LOW_PRECISION_ENABLE=1 as an environment variable. No code changes needed.</p>

    <h2>05 &mdash; Integration: how it fits into your code</h2>
    <p>RCCLX plugs into Torchcomms, Meta's unified communication API built on PyTorch. The goal is that you write your model code once and it works on AMD, NVIDIA, or future backends, without touching the communication layer.</p>
    <pre><code>import torchcomms
        # Initialize a communicator on AMD (HIP) device
        comm = torchcomms.new_comm("rcclx", torch.device("hip"), name="my_comm")
        t = torch.full((10, 20), value=comm.rank, dtype=torch.float)
        # Drop-in AllReduce, same API as NVIDIA/NCCLX backend
        comm.allreduce(t, torchcomms.ReduceOp.SUM, async_op=False)</code></pre>
    <p>Notice: the only AMD-specific thing is "rcclx" and torch.device("hip"). Everything else, the API surface, the semantics, is identical to what NVIDIA users use. That's the point.</p>

    <h2>06 &mdash; Why it matters: the bigger story, GPU vendor diversification</h2>
    <p>RCCLX is part of a broader trend: hyperscalers are no longer building exclusively for NVIDIA. Meta is running real production workloads on AMD MI300X (and next, MI350) GPUs. This requires not just hardware acquisition but software parity, the same performance tricks they built on NVIDIA need to exist on AMD too.</p>
    <p>Previously, Meta open-sourced CTran, a custom transport layer for NVIDIA. RCCLX ports CTran's ideas (like AllToAllvDynamic, a GPU-resident collective) to AMD. The throughput and latency benchmarks here, tested on real Meta inference workloads, suggest AMD is becoming a credible alternative, not just a fallback. For the broader ecosystem, open-sourcing RCCLX means any team using AMD GPUs for LLM training or inference can drop in these gains today.</p>

    <div class="callout">
    <div class="k">Key takeaway</div>
    <p>GPU communication, not compute, is quietly becoming the key bottleneck in LLM inference. Meta's RCCLX demonstrates two durable ideas: skip the ring topology when you can access memory directly, and compress before you transmit. The 10% TTIT improvement and 7% throughput gain come not from faster chips, but from smarter use of the interconnect between them. As AMD hardware scales up, these software-layer wins compound fast.</p>
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
