use std::fs;
use std::path::PathBuf;

use anyhow::Result;
use clap::Parser;
use kanki_domain::{CardId, Counts, ReviewCard, ReviewSession, SessionEffect, Side};
use serde::Serialize;

#[derive(Debug, Parser)]
#[command(name = "kanki", about = "Kindle-native Anki reviewer")]
struct Cli {
    /// Run deterministic architecture/runtime checks without touching a collection.
    #[arg(long)]
    self_test: bool,
    /// Write the persistent reviewer shell to a file for inspection.
    #[arg(long)]
    dump_shell: Option<PathBuf>,
}

#[derive(Debug, Serialize)]
struct SelfTestReport {
    build_version: &'static str,
    renderer_protocol: u32,
    reviewer_sha256: String,
    persistent_qa: bool,
    state_machine: bool,
    result: &'static str,
}

fn demo_card() -> ReviewCard {
    ReviewCard {
        id: CardId(42),
        template_ordinal: 0,
        question_html: "<div class=\"front\">front</div>".into(),
        answer_html: "<div id=\"answer\">answer</div>".into(),
        css: ".front { font-size: 2em; }".into(),
        question_audio: vec![],
        answer_audio: vec![],
        counts: Counts {
            new: 1,
            learning: 0,
            review: 2,
        },
        intervals: ["1m".into(), "6m".into(), "1d".into(), "4d".into()],
    }
}

fn self_test() -> Result<()> {
    let shell = kanki_renderer::bootstrap_document();
    let persistent_qa = shell.matches("id=\"qa\"").count() == 1;
    let mut session = ReviewSession::default();
    let question = matches!(
        session.load(Some(demo_card())),
        SessionEffect::Render {
            side: Side::Question,
            ..
        }
    );
    let answer = matches!(
        session.show_answer()?,
        SessionEffect::Render {
            side: Side::Answer,
            ..
        }
    );
    let state_machine = question && answer;
    let report = SelfTestReport {
        build_version: env!("CARGO_PKG_VERSION"),
        renderer_protocol: 1,
        reviewer_sha256: kanki_renderer::runtime_sha256(),
        persistent_qa,
        state_machine,
        result: if persistent_qa && state_machine {
            "pass"
        } else {
            "fail"
        },
    };
    println!("{}", serde_json::to_string_pretty(&report)?);
    anyhow::ensure!(report.result == "pass", "self-test failed");
    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    if let Some(path) = cli.dump_shell {
        fs::write(path, kanki_renderer::bootstrap_document())?;
    }
    if cli.self_test {
        return self_test();
    }
    println!(
        "Kanki rewrite scaffold: device runtime is gated behind the rewrite acceptance matrix."
    );
    Ok(())
}
