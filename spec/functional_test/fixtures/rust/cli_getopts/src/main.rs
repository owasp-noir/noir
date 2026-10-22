use getopts::Options;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut opts = Options::new();
    opts.optopt("o", "output", "output file name", "NAME");
    opts.optflag("h", "help", "print this help menu");
    opts.reqopt("c", "config", "config file path", "FILE");

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
