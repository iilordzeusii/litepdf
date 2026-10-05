#[path = "../ops.rs"] mod ops;
fn main() { let a: Vec<String> = std::env::args().collect(); let r = ops::compress(&a[1], &a[2], a[3].parse().unwrap(), a[4].parse().unwrap()).unwrap(); println!("replaced {} of {}", r.0, r.1); }
