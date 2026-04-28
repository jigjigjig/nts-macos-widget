# NTS Widget Design Prompt

Use this prompt with a UI design model or designer:

> Design a native macOS WidgetKit widget for NTS radio.
>
> Product constraints are fixed and must not be expanded:
> - One widget only: `systemMedium`
> - Native macOS SwiftUI / WidgetKit feel
> - Live playback only
> - Two stations only: `NTS 1` and `NTS 2`
> - No show metadata
> - No artwork
> - No search
> - No menu bar concepts
> - No attempt to mimic the NTS website
>
> The widget lives on the Mac desktop and in Notification Center, so it must feel glanceable, calm, legible, and system-native.
>
> Visual direction:
> - Design a restrained utility widget with a slightly airy, "cloud-light" feeling expressed through softness, spacing, subtle depth, and rounded geometry, not literal cloud graphics.
> - Use Apple-native conventions: system typography, SF Symbols, semantic colors, clean hierarchy, and surfaces that still read well under widget rendering treatments.
> - The look should feel intentional and premium, but minimal. Avoid decorative noise, album-art placeholders, glossy skeuomorphism, or a web-card aesthetic.
>
> Content structure is fixed:
> - Top row: `NTS` label on the left, active station badge on the right
> - Middle row: one status line only
> - Bottom row: exactly three controls, in this order or a clearly equivalent layout: `1`, `2`, `Play/Pause`
>
> Status examples:
> - `Playing NTS 1`
> - `Playing NTS 2`
> - `Paused`
> - `Unavailable`
>
> Interaction design:
> - Station buttons should be clearly tappable/clickable and easy to differentiate.
> - The active station should be visually obvious without relying only on color.
> - The play/pause control should read as the primary action.
> - The design must remain legible at actual `systemMedium` widget size on macOS.
>
> Deliverables:
> - One polished `systemMedium` widget design
> - Variants for these states: idle, NTS 1 playing, NTS 2 playing, paused, error/unavailable
> - Short rationale for hierarchy, spacing, color behavior, and control emphasis
> - A compact spec for typography, spacing, corner radius, icon usage, and button treatments
>
> Important:
> - Prioritize clarity over personality.
> - Keep it buildable in SwiftUI with standard native components and light customization.
> - Do not introduce extra information, extra controls, or speculative features.
