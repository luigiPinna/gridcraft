
// PROBE (temporary, not to be committed): deepest n under the 896 KiB stack guard alone.
#[test]
fn probe_stack_per_call() {
    let forms: [(&str, fn(u32) -> String); 4] = [
        ("countdown", |n| format!("=LET(F,LAMBDA(me,n,IF(n<=0,0,1+me(me,n-1))),F(F,{n}))")),
        ("tail", |n| format!("=LET(F,LAMBDA(me,n,IF(n=0,0,me(me,n-1))),F(F,{n}))")),
        ("let", |n| format!("=LET(F,LAMBDA(me,n,IF(n<=0,0,LET(e,me(me,n-1),e+1))),F(F,{n}))")),
        ("map", |n| format!("=LET(F,LAMBDA(me,n,IF(n<=0,0,1+SUM(MAP({{1}},LAMBDA(v,me(me,n-1)))))),F(F,{n}))")),
    ];
    let handle = std::thread::Builder::new()
        .stack_size(64 * 1024 * 1024)
        .spawn(move || {
            let wb = Workbook::new();
            let mut out = Vec::new();
            for (name, f) in forms {
                let ok = |n: u32| matches!(crate::evaluate(&wb, 0, c("B1"), &f(n)), Value::Number(_));
                let (mut lo, mut hi) = (1u32, 20_000u32);
                while lo + 1 < hi {
                    let mid = (lo + hi) / 2;
                    if ok(mid) { lo = mid } else { hi = mid }
                }
                out.push(format!("PROBE {name}: deepest n {lo}, {} bytes per call", 917_504 / (lo + 1)));
            }
            out
        })
        .expect("spawn");
    for line in handle.join().expect("join") {
        println!("{line}");
    }
}
