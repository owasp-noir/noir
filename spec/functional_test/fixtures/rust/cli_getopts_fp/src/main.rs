use getopts;

// Unrelated struct that happens to expose a method named `optflag`, with a
// receiver variable that is never bound via `Options::new()`. Its calls must
// NOT be attributed as CLI flags — only the real getopts receiver (`opts`)
// should surface params.
struct FeatureToggle {
    enabled: bool,
}

impl FeatureToggle {
    fn optflag(&mut self, name: &str, note: &str) {
        println!("toggling {} ({})", name, note);
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    // Fully-qualified type annotation (`getopts::Options`) instead of the
    // bare `Options` — a legitimate style when a file only does
    // `use getopts;` rather than `use getopts::Options;`.
    let mut opts: getopts::Options = getopts::Options::new();
    opts.optopt("o", "output", "output file name", "NAME");
    opts.optflag("h", "help", "print this help menu");
    opts.reqopt("c", "config", "config file path", "FILE");

    let mut toggle = FeatureToggle { enabled: false };
    toggle.optflag("unrelated-noise", "second arg");

    let matches = match opts.parse(&args[1..]) {
        Ok(m) => m,
        Err(f) => panic!("{}", f.to_string()),
    };

    let token = std::env::var("API_TOKEN").unwrap();

    if matches.opt_present("h") {
        println!("help");
    }
    println!("{}", token);
}
