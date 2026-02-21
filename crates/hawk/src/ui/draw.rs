// ▛▞// hawk draw layer :: hawk.ui.draw
// @ctx ⫸ [topbar.table.footer]
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{
        block::BorderType,
        Block, Borders, Cell, Paragraph, Row, Table, Wrap,
    },
    Frame,
};

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use crate::app::{App, Liveness};

/// Block with borders; uses ASCII Plain borders on Windows to avoid ? from Unicode box-drawing.
fn block(borders: Borders, title: &str) -> Block {
    let b = Block::default().borders(borders);
    let b = if title.is_empty() { b } else { b.title(title) };
    #[cfg(windows)]
    let b = b.border_type(BorderType::Plain);
    b
}

pub fn draw_app(f: &mut Frame, app: &App) {
    let size = f.size();

    let outer = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // top bar
            Constraint::Min(0),    // body
            Constraint::Length(1), // footer
        ])
        .split(size);

    draw_top_bar(f, outer[0], app);
    draw_body(f, outer[1], app);
    draw_footer(f, outer[2]);
}

fn draw_top_bar(f: &mut Frame, area: Rect, app: &App) {
    let (total, ok, warn, fail, stale, dead) = app.counts_by_state();
    let now = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_default();

    let text = Line::from(vec![
        Span::styled("HAWK", Style::default().add_modifier(Modifier::BOLD)),
        Span::raw("  "),
        Span::raw(format!(
            "entities={}  ok={}  warn={}  fail={}  stale={}  dead={}",
            total, ok, warn, fail, stale, dead
        )),
        Span::raw("  "),
        Span::raw(format!(
            "frames={}  parse_err={}  io_err={}",
            app.frames_seen, app.parse_errors, app.io_errors
        )),
        Span::raw("  "),
        Span::raw(now),
    ]);

    let p = Paragraph::new(text)
        .block(block(Borders::ALL, "health at a glance"))
        .wrap(Wrap { trim: true });

    f.render_widget(p, area);
}

fn draw_body(f: &mut Frame, area: Rect, app: &App) {
    let cols = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(68), Constraint::Percentage(32)])
        .split(area);

    draw_entity_table(f, cols[0], app);
    draw_tail(f, cols[1], app);
}

fn draw_footer(f: &mut Frame, area: Rect) {
    let text = Line::from(vec![
        Span::raw("q or esc: quit"),
        Span::raw("  |  "),
        Span::raw("source: stdin or unix socket (TSV HawkFrames)"),
    ]);
    let p = Paragraph::new(text).block(block(Borders::TOP, ""));
    f.render_widget(p, area);
}

fn draw_entity_table(f: &mut Frame, area: Rect, app: &App) {
    let now = OffsetDateTime::now_utc();
    let rows = app.sorted_entities().into_iter().take(200).map(|st| {
        let live = app.compute_entity_liveness(&st, now);
        let age = (now - st.last_seen).whole_seconds();

        let live_str = match live {
            Liveness::Active => "active",
            Liveness::Dream => "dream",
            Liveness::Stale => "stale",
            Liveness::Dead => "dead",
        };

        Row::new(vec![
            Cell::from(st.scope),
            Cell::from(st.id),
            Cell::from(st.kind),
            Cell::from(st.last_level.as_str().to_string()),
            Cell::from(live_str.to_string()),
            Cell::from(format!("{}s", age.max(0))),
            Cell::from(st.last_msg),
        ])
    });

    let header = Row::new(vec![
        Cell::from("scope"),
        Cell::from("id"),
        Cell::from("kind"),
        Cell::from("level"),
        Cell::from("state"),
        Cell::from("age"),
        Cell::from("last msg"),
    ])
    .style(Style::default().add_modifier(Modifier::BOLD));

    let table = Table::new(
        rows,
        [
            Constraint::Length(10),
            Constraint::Length(20),
            Constraint::Length(14),
            Constraint::Length(8),
            Constraint::Length(8),
            Constraint::Length(6),
            Constraint::Min(10),
        ],
    )
    .header(header)
    .block(block(Borders::ALL, "entities"))
    .column_spacing(1);

    f.render_widget(table, area);
}

fn draw_tail(f: &mut Frame, area: Rect, app: &App) {
    let mut lines: Vec<Line> = Vec::new();
    for s in app.tail.iter() {
        lines.push(Line::from(Span::raw(s.clone())));
    }

    let p = Paragraph::new(lines)
        .block(block(Borders::ALL, "event tail"))
        .wrap(Wrap { trim: false });

    f.render_widget(p, area);
}
// :: ∎
