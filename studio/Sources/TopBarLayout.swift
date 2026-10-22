import SwiftUI

/// **The top bar's three parts, shared out by what each can give up.**
///
/// Left (sidebar patch, film name), middle (the modes), right (the buttons).
/// Two flexible flanks round a ViewThatFits middle shared the space by
/// *flexibility*, so the modes were offered a fraction of what was free and
/// dropped to the one-pill menu at 1300 points when they needed about 430 —
/// his report, 2026-10-15: the bar "disappears way too fast".
///
/// Here the order is explicit. The right is whole. The left is allowed down
/// to its floor (the film's name shortened to a stub) before the middle is
/// asked to give anything; the middle is then offered every point that is
/// left and picks its widest form that fits. It sits dead centre on the
/// window while the left leaves room for that, and slides right only when it
/// must. Nothing is placed over anything else.
struct TopBarLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let h: CGFloat = proposal.height ?? 52
        guard let w = proposal.width else {
            let sum = subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width }
            return CGSize(width: sum, height: h)
        }
        // The least it can be: the left at its floor, the middle at its
        // smallest, the right whole.
        let least = subviews[0].sizeThatFits(ProposedViewSize(width: 0, height: h)).width
            + subviews[1].sizeThatFits(ProposedViewSize(width: 0, height: h)).width
            + subviews[2].sizeThatFits(.unspecified).width
        return CGSize(width: max(w, least), height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let h = bounds.height
        let w = bounds.width
        let floorLeft = subviews[0].sizeThatFits(ProposedViewSize(width: 0, height: h)).width
        let right = subviews[2].sizeThatFits(.unspecified).width
        let room = max(0, w - floorLeft - right)
        let mid = subviews[1].sizeThatFits(ProposedViewSize(width: room, height: h)).width
        // Dead centre if the left can stand it; otherwise as far left as the
        // left's floor allows, and never into the right.
        var x = w / 2 - mid / 2
        x = min(x, w - right - mid)
        x = max(x, floorLeft)
        let y = bounds.midY
        subviews[0].place(at: CGPoint(x: bounds.minX, y: y), anchor: .leading,
                          proposal: ProposedViewSize(width: x, height: h))
        subviews[1].place(at: CGPoint(x: bounds.minX + x, y: y), anchor: .leading,
                          proposal: ProposedViewSize(width: mid, height: h))
        subviews[2].place(at: CGPoint(x: bounds.minX + x + mid, y: y), anchor: .leading,
                          proposal: ProposedViewSize(width: max(0, w - x - mid), height: h))
    }
}
