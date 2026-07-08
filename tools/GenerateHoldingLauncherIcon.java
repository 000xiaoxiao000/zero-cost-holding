import java.awt.*;
import java.awt.geom.*;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

/**
 * Generates launcher PNGs for all Android mipmap densities.
 *
 * Icon concept: a gold seed at the bottom sprouts a green stem with two leaves.
 * The stem tip flows into a rising stock-chart trend line, ending with an
 * upward arrow — merging "seed / sprout" with "rising market" in one mark.
 *
 * Run from the project root:
 *   javac tools/GenerateHoldingLauncherIcon.java -d tools/
 *   java -cp tools GenerateHoldingLauncherIcon
 */
public class GenerateHoldingLauncherIcon {

    public static void main(String[] args) throws Exception {
        int[]    sizes = {48, 72, 96, 144, 192};
        String[] dirs  = {"mipmap-mdpi", "mipmap-hdpi", "mipmap-xhdpi",
                          "mipmap-xxhdpi", "mipmap-xxxhdpi"};

        for (int i = 0; i < sizes.length; i++) {
            BufferedImage img = drawIcon(sizes[i]);
            File dir = new File("android/app/src/main/res/" + dirs[i]);
            dir.mkdirs();
            ImageIO.write(img, "png", new File(dir, "ic_launcher.png"));
            ImageIO.write(img, "png", new File(dir, "ic_launcher_round.png"));
            System.out.println("Written " + dirs[i] + " (" + sizes[i] + "px)");
        }
    }

    private static BufferedImage drawIcon(int size) {
        BufferedImage img = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING,    RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING,       RenderingHints.VALUE_RENDER_QUALITY);
        g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL,  RenderingHints.VALUE_STROKE_PURE);

        // Scale factor: all coordinates are defined in 108-unit space
        float s = size / 108f;

        drawBackground(g, size, s);
        drawSeed(g, s);
        drawStemAndLeaves(g, s);
        drawChartLine(g, s);
        drawArrow(g, s);

        g.dispose();
        return img;
    }

    // ── Background ──────────────────────────────────────────────────────────

    private static void drawBackground(Graphics2D g, int size, float s) {
        float corner = 22 * s;
        RoundRectangle2D bg = new RoundRectangle2D.Float(0, 0, size, size, corner, corner);

        GradientPaint grad = new GradientPaint(
            0,    0,    new Color(0x0D1117),
            size, size, new Color(0x071120)
        );
        g.setPaint(grad);
        g.fill(bg);

        // Subtle blue inner glow at top-left
        g.setPaint(new Color(0x1F6FEB, false) {
            { }
            @Override public Color brighter() { return this; }
        });
        // soft radial-like bleed — approximate with transparent fill
        g.setColor(new Color(0x1F, 0x6F, 0xEB, 20));
        g.fill(new Ellipse2D.Float(-size * 0.2f, -size * 0.2f, size * 0.9f, size * 0.9f));
    }

    // ── Gold seed ────────────────────────────────────────────────────────────

    private static void drawSeed(Graphics2D g, float s) {
        float cx = 54 * s, cy = 80 * s;
        float rx = 8 * s, ry = 5.5f * s;

        // outer glow
        g.setColor(new Color(0xD4, 0xA0, 0x17, 45));
        g.fill(new Ellipse2D.Float(cx - rx * 1.6f, cy - ry * 1.6f,
                                   rx * 3.2f, ry * 3.2f));

        // seed body gradient
        GradientPaint seedGrad = new GradientPaint(
            cx - rx, cy - ry, new Color(0xFDE68A),
            cx + rx, cy + ry, new Color(0xA87010)
        );
        g.setPaint(seedGrad);
        g.fill(new Ellipse2D.Float(cx - rx, cy - ry, rx * 2, ry * 2));

        // center crease
        g.setColor(new Color(0x7A, 0x58, 0x00, 160));
        g.setStroke(new BasicStroke(1.2f * s, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
        g.drawLine(Math.round(cx), Math.round(cy - ry + 1 * s),
                   Math.round(cx), Math.round(cy + ry - 1 * s));
    }

    // ── Stem & leaves ────────────────────────────────────────────────────────

    private static void drawStemAndLeaves(Graphics2D g, float s) {
        Color stemColor = new Color(0x00A870);

        // stem
        g.setColor(stemColor);
        g.setStroke(new BasicStroke(3.2f * s, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
        g.drawLine(Math.round(54 * s), Math.round(75 * s),
                   Math.round(54 * s), Math.round(36 * s));

        // left leaf
        GeneralPath leftLeaf = new GeneralPath();
        leftLeaf.moveTo(54 * s, 62 * s);
        leftLeaf.curveTo(54 * s, 62 * s, 41 * s, 58 * s, 39 * s, 50 * s);
        leftLeaf.curveTo(39 * s, 50 * s, 49 * s, 47 * s, 54 * s, 55 * s);
        leftLeaf.closePath();
        g.setColor(new Color(0x00, 0xA8, 0x70, 220));
        g.fill(leftLeaf);

        // right leaf (lighter, teal)
        GeneralPath rightLeaf = new GeneralPath();
        rightLeaf.moveTo(54 * s, 56 * s);
        rightLeaf.curveTo(54 * s, 56 * s, 66 * s, 52 * s, 68 * s, 44 * s);
        rightLeaf.curveTo(68 * s, 44 * s, 58 * s, 41 * s, 54 * s, 50 * s);
        rightLeaf.closePath();
        g.setColor(new Color(0x39, 0xE0, 0xB4, 195));
        g.fill(rightLeaf);
    }

    // ── Rising chart line ────────────────────────────────────────────────────

    private static void drawChartLine(Graphics2D g, float s) {
        // node coordinates (108-space)
        float[][] nodes = {
            {33, 64}, {43, 56}, {54, 58}, {67, 44}, {78, 35}
        };

        Path2D line = new Path2D.Float();
        line.moveTo(nodes[0][0] * s, nodes[0][1] * s);
        for (int i = 1; i < nodes.length; i++) {
            line.lineTo(nodes[i][0] * s, nodes[i][1] * s);
        }

        // glow halo
        g.setStroke(new BasicStroke(8 * s, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
        g.setColor(new Color(0x39, 0xE0, 0xB4, 50));
        g.draw(line);

        // main teal line
        g.setStroke(new BasicStroke(3.5f * s, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
        g.setColor(new Color(0x39E0B4));
        g.draw(line);

        // chart nodes
        Color[] nodeColors = {
            new Color(0x39E0B4),
            new Color(0x39E0B4),
            new Color(0x39E0B4),
            new Color(0xD4A017),
            new Color(0xFDE68A)   // top node: bright gold
        };
        float[] radii = {2.8f, 2.8f, 2.8f, 3f, 4f};

        for (int i = 0; i < nodes.length; i++) {
            float r = radii[i] * s;
            float nx = nodes[i][0] * s - r;
            float ny = nodes[i][1] * s - r;
            g.setColor(nodeColors[i]);
            g.fill(new Ellipse2D.Float(nx, ny, r * 2, r * 2));
        }
    }

    // ── Up-arrow at top-right ────────────────────────────────────────────────

    private static void drawArrow(Graphics2D g, float s) {
        float tx = 78 * s, ty = 35 * s;
        float arm = 5 * s;

        g.setColor(new Color(0xD4A017));
        g.setStroke(new BasicStroke(2.5f * s, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));

        // left arm of arrow
        g.drawLine(Math.round(tx), Math.round(ty),
                   Math.round(tx - arm), Math.round(ty + arm));
        // right arm of arrow
        g.drawLine(Math.round(tx), Math.round(ty),
                   Math.round(tx + arm), Math.round(ty + arm));
        // shaft
        g.drawLine(Math.round(tx), Math.round(ty),
                   Math.round(tx), Math.round(ty + arm * 1.8f));
    }
}
