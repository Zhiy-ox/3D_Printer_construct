from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


OUT = "README.PDF"


def make_styles():
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="GuideTitle",
            parent=styles["Title"],
            fontName="Helvetica-Bold",
            fontSize=22,
            leading=26,
            textColor=colors.HexColor("#0B2545"),
            alignment=TA_CENTER,
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="Subtitle",
            parent=styles["Normal"],
            fontName="Helvetica",
            fontSize=10.5,
            leading=14,
            textColor=colors.HexColor("#4B5563"),
            alignment=TA_CENTER,
            spaceAfter=14,
        )
    )
    styles.add(
        ParagraphStyle(
            name="H1Custom",
            parent=styles["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=15,
            leading=18,
            textColor=colors.HexColor("#2E74B5"),
            spaceBefore=14,
            spaceAfter=7,
        )
    )
    styles.add(
        ParagraphStyle(
            name="H2Custom",
            parent=styles["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=12,
            leading=15,
            textColor=colors.HexColor("#1F4D78"),
            spaceBefore=10,
            spaceAfter=5,
        )
    )
    styles.add(
        ParagraphStyle(
            name="BodyCustom",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=9.7,
            leading=12.2,
            spaceAfter=5,
        )
    )
    styles.add(
        ParagraphStyle(
            name="Small",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=8.7,
            leading=10.8,
            textColor=colors.HexColor("#374151"),
            spaceAfter=4,
        )
    )
    styles.add(
        ParagraphStyle(
            name="CodeBox",
            parent=styles["Code"],
            fontName="Courier",
            fontSize=8,
            leading=10,
            leftIndent=0,
            rightIndent=0,
            borderColor=colors.HexColor("#D1D5DB"),
            borderWidth=0.5,
            borderPadding=6,
            backColor=colors.HexColor("#F8FAFC"),
            spaceBefore=4,
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="Callout",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=9.3,
            leading=12,
            borderColor=colors.HexColor("#CBD5E1"),
            borderWidth=0.6,
            borderPadding=7,
            backColor=colors.HexColor("#F4F6F9"),
            spaceBefore=4,
            spaceAfter=8,
        )
    )
    return styles


def p(text, style):
    return Paragraph(text, style)


def code(text, styles):
    return Preformatted(text.strip("\n"), styles["CodeBox"])


def bullets(items, styles):
    return ListFlowable(
        [ListItem(p(item, styles["BodyCustom"]), leftIndent=12) for item in items],
        bulletType="bullet",
        start="circle",
        leftIndent=14,
        bulletFontName="Helvetica",
        bulletFontSize=7,
    )


def param_table(rows, styles):
    data = [[p("<b>Parameter</b>", styles["Small"]), p("<b>Purpose</b>", styles["Small"]), p("<b>Typical use</b>", styles["Small"])]]
    for name, purpose, typical in rows:
        data.append([p(f"<font name='Courier'>{name}</font>", styles["Small"]), p(purpose, styles["Small"]), p(typical, styles["Small"])])
    table = Table(data, colWidths=[1.42 * inch, 3.15 * inch, 1.68 * inch], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E8EEF5")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#0B2545")),
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#CBD5E1")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def two_col_table(rows, styles):
    data = [[p(f"<b>{left}</b>", styles["Small"]), p(right, styles["Small"])] for left, right in rows]
    table = Table(data, colWidths=[1.65 * inch, 4.6 * inch], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#CBD5E1")),
                ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#F2F4F7")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#6B7280"))
    canvas.drawString(inch, 0.55 * inch, "TPP-DLW Toolpath Generator - New User Guide")
    canvas.drawRightString(7.5 * inch, 0.55 * inch, f"Page {doc.page}")
    canvas.restoreState()


def build():
    styles = make_styles()
    doc = SimpleDocTemplate(
        OUT,
        pagesize=letter,
        rightMargin=0.82 * inch,
        leftMargin=0.82 * inch,
        topMargin=0.78 * inch,
        bottomMargin=0.78 * inch,
        title="TPP-DLW Toolpath Generator New User Guide",
        author="Codex",
    )

    story = []
    story.append(p("TPP-DLW Toolpath Generator", styles["GuideTitle"]))
    story.append(p("New User Guide for STL-to-TXT Conversion", styles["Subtitle"]))
    story.append(
        p(
            "This guide explains how to convert an STL file into the tab-separated segment text "
            "format used by the LabVIEW writing interface. It focuses on the fastest current workflow "
            "and the checks that prevent false toolpath lines.",
            styles["BodyCustom"],
        )
    )
    story.append(
        p(
            "<b>Recommended path:</b> use <font name='Courier'>heightmap_raster_export.m</font> "
            "for pixel-exact height-map STL/CSV files. Use the modular <font name='Courier'>tppdlw_process</font> pipeline "
            "for general STL/STEP workflows or the GUI.",
            styles["Callout"],
        )
    )

    story.append(p("1. Project Layout", styles["H1Custom"]))
    story.append(
        two_col_table(
            [
                ("Height-map raster", "<font name='Courier'>heightmap_raster_export.m</font> - direct height-map STL/CSV to TXT exporter."),
                ("Contour STL exporter", "<font name='Courier'>stl_slice_export_mm_woodpile_true_resample.m</font> - contour-slicing STL exporter for non-height-map cases."),
                ("General pipeline", "<font name='Courier'>tppdlw_process.m</font> plus <font name='Courier'>core/</font> helpers for STL/STEP imports and arbitrary scan angles."),
                ("Preview tools", "<font name='Courier'>viz/preview_toolpath.m</font>, <font name='Courier'>viz/preview_3d.m</font>, and layer comparison tools."),
                ("Examples/tests", "<font name='Courier'>examples/</font> and <font name='Courier'>tests/</font> show basic usage and expected output format."),
                ("Generated data", "<font name='Courier'>output/</font>, STL files, and large TXT exports are ignored by Git by default."),
            ],
            styles,
        )
    )

    story.append(p("2. Quick Start", styles["H1Custom"]))
    story.append(p("From MATLAB, open the project folder and run:", styles["BodyCustom"]))
    story.append(
        code(
            """
cd('/path/to/3D_Printer_construct')
run('heightmap_raster_export.m')
""",
            styles,
        )
    )
    story.append(
        bullets(
            [
                "Set <font name='Courier'>HeightMapPath</font> to your input height-map STL or CSV file.",
                "Set <font name='Courier'>OutTxt</font> to the TXT file you want to create.",
                "Set <font name='Courier'>BaseHeight</font> if the source CSV needs a support base; leave it at 0 if the STL already includes one.",
                "Start with coarse <font name='Courier'>XYPitch</font> and <font name='Courier'>DZ</font> for preview runs, then restore final values for production.",
                "Read the console summary. Height-map raster export should not report odd contour-crossing warnings.",
            ],
            styles,
        )
    )

    story.append(p("3. Output Format", styles["H1Custom"]))
    story.append(
        p(
            "The output TXT is tab-separated, with one row per laser-on scan segment or Z transition:",
            styles["BodyCustom"],
        )
    )
    story.append(code("X1    Y1    Z1    X2    Y2    Z2", styles))
    story.append(
        bullets(
            [
                "Rows where <font name='Courier'>Z1 == Z2</font> are scan/write segments.",
                "Rows where <font name='Courier'>Z1 != Z2</font> are layer-to-layer Z moves.",
                "Coordinates are in millimeters.",
                "The height-map raster exporter writes positive build height as negative stage Z when <font name='Courier'>StageZConvention</font> is true.",
            ],
            styles,
        )
    )

    story.append(PageBreak())
    story.append(p("4. Main Parameters", styles["H1Custom"]))
    story.append(
        param_table(
            [
                ("HeightMapPath", "Input height-map STL or CSV file.", "Use this path for pixel-exact height maps."),
                ("OutTxt", "Destination tab-separated TXT file.", "Use <font name='Courier'>output/name.txt</font> for generated files."),
                ("TargetMaxXY", "Scales the model to a target XY footprint in mm.", "Scalar for square fit, or [maxX maxY]."),
                ("XYPitch", "Spacing between adjacent raster scanlines.", "Larger for preview, final value for production."),
                ("DZ", "Layer thickness / vertical slicing step.", "Larger for preview, final value for production."),
                ("PixelPitch", "Source pixel pitch for CSV input.", "STL can read this from the generated header."),
                ("BaseHeight", "Support base height in source units.", "Use 0 for STL that already includes a base; use 0.5 for a micron-valued CSV needing a 0.5 um base."),
                ("WoodpileMode", "Alternates horizontal and vertical writing by layer.", "Keep true for orthogonal resampling."),
                ("Serpentine", "Alternates scan direction to reduce travel.", "Usually true."),
                ("CoordMode", "Uses voxel edges or grid centers for endpoints.", "Use edges for full-width base rows."),
                ("StageZConvention", "Writes positive build height as negative stage Z.", "Usually true for the printer stage convention."),
                ("OutputSignificantDigits", "Controls compact TXT numeric precision.", "Default 6 keeps values like 0.0002 readable."),
                ("Tolerance_mm", "Height comparison tolerance in mm.", "Default is usually fine."),
            ],
            styles,
        )
    )

    story.append(p("5. Size and Pixel Pitch", styles["H1Custom"]))
    story.append(
        bullets(
            [
                "<font name='Courier'>PixelPitch</font> describes the original height-map pixel spacing in source units, such as 6 for a 6 um CSV pixel.",
                "<font name='Courier'>TargetMaxXY</font> controls the final maximum XY footprint in millimeters.",
                "<font name='Courier'>XYPitch</font> is the printer raster scanline spacing in millimeters. It controls write density and TXT size, not the source model footprint.",
                "If <font name='Courier'>TargetMaxXY</font> is set, the final source-pixel pitch is derived from target size and grid count. For a 335 x 335 map at 1.005 mm, one source pixel becomes 1.005 / 335 = 0.003 mm.",
                "<font name='Courier'>BaseHeight</font> is added in <font name='Courier'>heightmap_to_segments</font> before raster scanlines are generated, so it creates full support-base scanlines across the height-map footprint.",
            ],
            styles,
        )
    )

    story.append(p("6. Preview and Quality Checks", styles["H1Custom"]))
    story.append(p("After generating a TXT file, preview a layer before printing:", styles["BodyCustom"]))
    story.append(
        code(
            """
addpath(genpath(pwd))
segments = load('output/Final.txt');
preview_toolpath(segments, 'Layer', 1, 'Mode', '2d')
preview_3d(segments, 'EveryN', 2)
""",
            styles,
        )
    )
    story.append(
        p(
            "Before sending a file to the printer, check for long strokes that cross empty space, out-of-bounds coordinates, unexpected zero-length rows, and unusually high segment counts on one layer.",
            styles["BodyCustom"],
        )
    )
    story.append(
        p(
            "If the first rows are short fragments along a boundary such as X = 0, a contour-slicing workflow is being used. Use heightmap_raster_export.m for pixel-exact height-map data so the file starts with hatch-fill rows.",
            styles["Callout"],
        )
    )
    story.append(
        p(
            "<b>Important:</b> the contour-slicing fallback skips unresolved odd scanlines instead of force-pairing them. For pixel-exact height maps, prefer the raster workflow so contour crossings are not used at all.",
            styles["Callout"],
        )
    )

    story.append(
        KeepTogether(
            [
                p("7. Troubleshooting", styles["H1Custom"]),
                two_col_table(
                    [
                        ("Long lines across empty regions", "Usually caused by using contour slicing on height-map data. Use height-map raster export first."),
                        ("Very slow conversion", "Increase <font name='Courier'>XYPitch</font> and <font name='Courier'>DZ</font> for preview."),
                        ("Missing small features", "Check whether <font name='Courier'>XYPitch</font> or <font name='Courier'>DZ</font> is too coarse."),
                        ("TXT is huge", "This is expected for fine pitch and large footprints. Keep generated TXT files under <font name='Courier'>output/</font> so Git ignores them."),
                        ("STL import fails", "Confirm the STL is binary or valid ASCII, not truncated, and that the file path is correct."),
                    ],
                    styles,
                ),
            ]
        )
    )

    story.append(p("8. Recommended Workflow", styles["H1Custom"]))
    story.append(
        bullets(
            [
                "<b>Preview pass:</b> use coarse pitch and layer height; generate quickly and inspect several layers.",
                "<b>Geometry check:</b> confirm the recovered height-map pitch, base height, and output span match the intended print.",
                "<b>Final pass:</b> restore production <font name='Courier'>XYPitch</font> and <font name='Courier'>DZ</font>; regenerate TXT.",
                "<b>Visual QA:</b> preview first, middle, and last layers; check that no scanline crosses empty space.",
                "<b>Archive:</b> commit code/config changes, not large generated files. Keep STL/TXT outputs ignored unless you intentionally need to version them.",
            ],
            styles,
        )
    )

    story.append(p("9. Quick Checklist Before Printing", styles["H1Custom"]))
    story.append(
        two_col_table(
            [
                ("[ ] Height-map source is correct", "Right file, right units, expected base height and bounding box."),
                ("[ ] Parameters reviewed", "Target size, XY pitch, DZ, coordinate mode, and output path are intentional."),
                ("[ ] Console warnings reviewed", "No unexpected truncated STL, missing height-map cells, or out-of-bounds warnings."),
                ("[ ] Layers previewed", "First, middle, and final layers look physically plausible."),
                ("[ ] Output format checked", "TXT has six numeric columns and the expected number of layers."),
                ("[ ] Generated files managed", "Large STL/TXT files are kept out of Git unless deliberately tracked."),
            ],
            styles,
        )
    )

    story.append(Spacer(1, 12))
    story.append(
        p(
            "For maintainers: keep the false-line prevention behavior conservative. Skipping an unresolved scanline is preferable to writing a long segment across empty space.",
            styles["Callout"],
        )
    )

    doc.build(story, onFirstPage=footer, onLaterPages=footer)


if __name__ == "__main__":
    build()
