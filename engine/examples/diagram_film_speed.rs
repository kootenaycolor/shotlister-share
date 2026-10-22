//! How long a plan takes on a full-size film — 184 scenes, eight shots each —
//! where every drag frame asks for the plan, its context and its picture:
//! `cargo run --release --example diagram_film_speed`.
fn main() {
    use shotlister_engine::diagram::{render, wire};
    use shotlister_engine::{json, DeviceId, Doc};
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Big");
    let mut scenes = vec![];
    for n in 1..=184 {
        let s = d.create_scene(&n.to_string());
        for _ in 0..8 {
            d.add_shot_to_scene(s);
        }
        scenes.push(s);
    }
    let scene = scenes[90];
    let mut els = String::new();
    for i in 0..120 {
        let kind = ["wall", "set", "camera", "cast", "light"][i % 5];
        els.push_str(&format!(r#"{}{{"kind":"{kind}","x":{},"y":{},"x2":{},"y2":{},"sym":"sofa"}}"#, if i > 0 { "," } else { "" }, i % 12, i / 12, i % 12 + 1, i / 12));
    }
    d.diagram_edit(scene, &json::parse(&format!(r#"{{"op":"add","els":[{els}]}}"#)).unwrap()).unwrap();
    let time = |what: &str, f: &mut dyn FnMut()| {
        let t = std::time::Instant::now();
        for _ in 0..20 {
            f();
        }
        println!("{what}: {:?}", t.elapsed() / 20);
    };
    time("read the plan", &mut || drop(d.diagram(scene)));
    time("its context", &mut || drop(d.diagram_context(scene)));
    let plan = d.diagram(scene);
    let ctx = d.diagram_context(scene);
    time("its picture", &mut || drop(wire::payload(&plan, &ctx, &render::Options::default())));
    time("counts for every scene", &mut || drop(d.diagram_counts()));
    let id = plan.els[0].id.clone();
    let mut x = 0.0;
    time("one move, written", &mut || {
        x += 0.1;
        d.diagram_edit(scene, &json::parse(&format!(r#"{{"op":"move","ids":["{id}"],"dx":{x},"dy":0}}"#)).unwrap()).unwrap();
    });
}
