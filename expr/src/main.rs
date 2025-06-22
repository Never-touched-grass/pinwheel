use rhai::{Engine, EvalAltResult, FLOAT};
use std::env;
fn eval() -> Result<rhai::Dynamic, Box<EvalAltResult>>{
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        println!("Usage: {} <expression>", args[0]);
        std::process::exit(1);
    }
    let expr = &args[1];
    let mut engine = Engine::new();
    engine.register_fn("/", |x: FLOAT, y: FLOAT| x/y);
    engine.register_fn("*", |x: FLOAT, y: FLOAT| x*y);
    engine.register_fn("+", |x: FLOAT, y: FLOAT| x+y);
    engine.register_fn("-", |x: FLOAT, y: FLOAT| x-y);
    engine.eval::<rhai::Dynamic>(expr)
}
fn main(){
    match eval(){
        Ok(result) => println!("{}", result),
        Err(e) => eprintln!("{}", e)
    }
}
