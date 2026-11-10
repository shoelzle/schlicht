import Toybox.Lang;

//! Positions shared by the view and the input delegate, in px on a 454 px
//! screen. Multiply by scale = screen width / 454.
module Layout {
    const DESIGN_SIZE = 454.0;

    // Radius of the circle of minute dots, as far out as possible.
    const DIAL_DOT_RADIUS = 219.0;

    // Notification dots: first dot above the centre, column grows upwards.
    const DOTS_FIRST_Y = 163.0;

    // Heart (left, 9 o'clock) and date (right, 3 o'clock): their inner edges
    // are this far from the centre, on both sides the same. The heart rate
    // number grows outwards, so the heart itself never moves.
    const INFO_GAP = 82.0;

    // Font size of date and heart rate; the heart is exactly as tall as the
    // digits (derived from the font's ascent in SchlichtView.capHeight).
    const INFO_FONT_SIZE = 29.9;

    // Day arc.
    const ARC_RADIUS = 193.0;
    const ARC_LABEL_RADIUS = 163.0;
    const ARC_LABEL_OFFSET_DEG = 15.0;
    // Long days (> 11 h): the arc spirals inwards by this much per 12 hours.
    const SPIRAL_GAP = 8.0;
}
