# Desktop water-reminder girl: a transparent, always-on-top window that walks
# along the bottom of the screen, asks you to drink water, then walks away.
# Message comes from env var WATER_MSG. Writes "drank", "later" or "dismissed" to stdout.

$source = @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class WaterGirl : Form
{
    int W = 440; const int H = 300;
    enum State { WalkIn, Talk, WalkOut }

    State state = State.WalkIn;
    string message, title = "Hey there!", sub;
    string result = "dismissed";
    double t = 0;
    int stopX, screenRight, groundY;
    int talkFrames = 0;
    Rectangle btnDrank = new Rectangle(185, 118, 235, 38);
    Rectangle btnLater = new Rectangle(185, 164, 235, 38);
    int hover = 0;
    Timer timer = new Timer();

    public static string Run(string msg, string assets)
    {
        Application.EnableVisualStyles();
        var f = new WaterGirl(msg, assets);
        Application.Run(f);
        return f.result;
    }

    List<Bitmap> walkF = new List<Bitmap>(), talkF = new List<Bitmap>();
    List<int> walkD = new List<int>(), talkD = new List<int>();
    int spriteW = 0, spriteH = 0, shift = 0, bubbleX = 100;
    double spriteMs = 0;

    static void LoadGif(string file, List<Bitmap> frames, List<int> delays)
    {
        using (var img = Image.FromFile(file))
        {
            int n = 1;
            FrameDimension fd = null;
            if (img.FrameDimensionsList.Length > 0) { fd = new FrameDimension(img.FrameDimensionsList[0]); n = img.GetFrameCount(fd); }
            byte[] d = null;
            try { d = img.GetPropertyItem(0x5100).Value; } catch { }
            for (int i = 0; i < n; i++)
            {
                if (fd != null) img.SelectActiveFrame(fd, i);
                frames.Add(new Bitmap(img));
                int dl = (d != null && d.Length >= (i + 1) * 4) ? BitConverter.ToInt32(d, i * 4) * 10 : 100;
                delays.Add(dl < 30 ? 100 : dl);
            }
        }
    }

    // name.gif, or name.png, or name_1.png, name_2.png, ...
    static void LoadSet(string dir, string name, List<Bitmap> frames, List<int> delays)
    {
        try
        {
            string gif = Path.Combine(dir, name + ".gif");
            if (File.Exists(gif)) { LoadGif(gif, frames, delays); return; }
            string png = Path.Combine(dir, name + ".png");
            if (File.Exists(png)) { LoadGif(png, frames, delays); return; }
            for (int i = 1; i < 200; i++)
            {
                string f = Path.Combine(dir, name + "_" + i + ".png");
                if (!File.Exists(f)) break;
                LoadGif(f, frames, delays);
            }
        }
        catch { frames.Clear(); delays.Clear(); }
    }

    List<Bitmap> Pick(bool walking)
    {
        if (walking) return walkF;
        return talkF.Count > 0 ? talkF : walkF;
    }

    void DrawSprite(Graphics g, bool walking)
    {
        var frames = Pick(walking);
        var delays = (walking || talkF.Count == 0) ? walkD : talkD;
        int idx = 0;
        if (frames.Count > 1 && (walking || talkF.Count > 0))
        {
            int total = 0; foreach (int d in delays) total += d;
            double pos = spriteMs % total;
            int acc = 0;
            for (int i = 0; i < frames.Count; i++) { acc += delays[i]; if (pos < acc) { idx = i; break; } }
        }
        else if (frames.Count > 1) idx = 0;
        var bmp = frames[idx];
        float scale = Math.Min(170f / bmp.Width, 240f / bmp.Height);
        float w = bmp.Width * scale, h = bmp.Height * scale;
        float bob = walking ? (float)(Math.Abs(Math.Sin(t * 10)) * -3) : 0;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.DrawImage(bmp, 10, H - 8 - h + bob, w, h);
    }

    WaterGirl(string msg, string assets)
    {
        message = msg; sub = msg;
        if (!string.IsNullOrEmpty(assets) && Directory.Exists(assets))
        {
            LoadSet(assets, "walk", walkF, walkD);
            LoadSet(assets, "talk", talkF, talkD);
            if (walkF.Count == 0 && talkF.Count > 0) { walkF.AddRange(talkF); walkD.AddRange(talkD); }
        }
        if (walkF.Count > 0)
        {
            var b0 = walkF[0];
            float sc = Math.Min(170f / b0.Width, 240f / b0.Height);
            spriteW = (int)(b0.Width * sc); spriteH = (int)(b0.Height * sc);
            shift = Math.Max(0, spriteW - 130);
            W += shift; bubbleX = 152 + shift;
            btnDrank.X += shift; btnLater.X += shift;
        }
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(W, H);
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        screenRight = wa.Right;
        groundY = wa.Bottom - H;
        stopX = wa.Left + wa.Width / 2 - 200;
        Location = new Point(wa.Left - W, groundY + 6);
        timer.Interval = 30;
        timer.Tick += Tick;
        Load += (s, e) => timer.Start();
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x80000 | 0x80 | 0x8 | 0x08000000; // LAYERED | TOOLWINDOW | TOPMOST | NOACTIVATE
            return cp;
        }
    }

    void Tick(object sender, EventArgs e)
    {
        t += 0.03; spriteMs += 30;
        int x = Left;
        if (state == State.WalkIn)
        {
            x += 6;
            if (x >= stopX) { x = stopX; state = State.Talk; }
        }
        else if (state == State.Talk)
        {
            talkFrames++;
            if (talkFrames > 33 * 90) GoAway("dismissed", "See you later!", "I'll remind you again.");
        }
        else
        {
            x += 6;
            if (x > screenRight) { timer.Stop(); Close(); return; }
        }
        Left = x;
        Top = groundY + 6;
        Render();
    }

    void GoAway(string res, string t1, string t2)
    {
        if (state != State.Talk) return;
        result = res; title = t1; sub = t2; state = State.WalkOut;
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (state != State.Talk) return;
        if (btnDrank.Contains(e.Location)) GoAway("drank", "Yay, thank you!", "Bye bye!");
        else if (btnLater.Contains(e.Location)) GoAway("later", "Okay, see you soon!", "I'll be back to remind you.");
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        hover = state != State.Talk ? 0 : btnDrank.Contains(e.Location) ? 1 : btnLater.Contains(e.Location) ? 2 : 0;
        Cursor = hover > 0 ? Cursors.Hand : Cursors.Default;
    }

    // ---------- drawing ----------

    static GraphicsPath Round(Rectangle r, int rad)
    {
        var p = new GraphicsPath();
        int d = rad * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    static void Limb(Graphics g, Brush b, float x, float y, float w, float h, float px, float py, float ang)
    {
        var st = g.Save();
        g.TranslateTransform(px, py);
        g.RotateTransform(ang);
        g.TranslateTransform(-px, -py);
        using (var path = Round(new Rectangle((int)x, (int)y, (int)w, (int)h), (int)(w / 2))) g.FillPath(b, path);
        g.Restore(st);
    }

    void Arm(Graphics g, Brush sleeve, Brush skin, float px, float py, float ang, int x)
    {
        var s = g.Save();
        g.TranslateTransform(px, py); g.RotateTransform(ang); g.TranslateTransform(-px, -py);
        using (var p = Round(new Rectangle(x, 76, 8, 34), 4)) g.FillPath(sleeve, p);
        g.FillEllipse(skin, x, 106, 8, 8);
        g.Restore(s);
    }

    void DrawGirl(Graphics g, bool walking)
    {
        var skin = new SolidBrush(Color.FromArgb(246, 214, 192));
        var hair = new SolidBrush(Color.FromArgb(58, 40, 36));
        var hairHi = new SolidBrush(Color.FromArgb(92, 68, 60));
        var topC = Color.FromArgb(36, 38, 56);
        var top = new SolidBrush(topC);
        var skirt = new SolidBrush(Color.FromArgb(52, 54, 84));
        var skirtLine = new Pen(Color.FromArgb(80, 84, 120), 1.2f);
        var boot = new SolidBrush(Color.FromArgb(32, 30, 38));
        var ink = new SolidBrush(Color.FromArgb(30, 24, 26));

        float swing = walking ? (float)(Math.Sin(t * 10) * 24) : 0;
        float bob = walking ? (float)(Math.Abs(Math.Sin(t * 10)) * -3) : (float)(Math.Sin(t * 4) * -1.5);
        float sway = walking ? (float)(Math.Sin(t * 10) * 5) : (float)(Math.Sin(t * 3) * 2);

        var st = g.Save();
        g.TranslateTransform(15, 119);
        g.ScaleTransform(0.95f, 0.95f);

        using (var sh = new SolidBrush(Color.FromArgb(55, 0, 0, 0))) g.FillEllipse(sh, 30, 175, 60, 9);

        // legs and boots
        float step = (float)(Math.Sin(Math.PI * swing / 180) * 16);
        Limb(g, skin, 51, 130, 8, 42, 55, 132, swing);
        g.FillEllipse(boot, 46 + step, 166, 17, 9);
        Limb(g, skin, 63, 130, 8, 42, 67, 132, -swing);
        g.FillEllipse(boot, 57 - step, 166, 17, 9);

        g.TranslateTransform(0, bob);

        // long straight hair behind
        var s1 = g.Save();
        g.TranslateTransform(60, 30); g.RotateTransform(sway * 0.4f); g.TranslateTransform(-60, -30);
        using (var bp = new GraphicsPath())
        {
            bp.AddBezier(34, 36, 22, 70, 26, 105, 30, 128);
            bp.AddBezier(30, 128, 45, 134, 75, 134, 90, 128);
            bp.AddBezier(90, 128, 94, 105, 98, 70, 86, 36);
            bp.CloseFigure();
            g.FillPath(hair, bp);
        }
        g.Restore(s1);

        // back arm
        Arm(g, top, skin, 41, 78, -swing, 37);

        // top and skirt
        using (var p = Round(new Rectangle(42, 72, 36, 36), 8)) g.FillPath(top, p);
        g.FillPolygon(skirt, new PointF[] { new PointF(42, 102), new PointF(78, 102), new PointF(91, 140), new PointF(29, 140) });
        g.DrawLine(skirtLine, 52, 106, 46, 138);
        g.DrawLine(skirtLine, 60, 106, 60, 139);
        g.DrawLine(skirtLine, 68, 106, 74, 138);

        // neck + head
        g.FillRectangle(skin, 55, 60, 10, 14);
        g.FillEllipse(skin, 36, 16, 48, 48);

        // side locks, bangs
        g.FillPolygon(hair, new PointF[] { new PointF(34, 38), new PointF(42, 44), new PointF(41, 76), new PointF(31, 84) });
        g.FillPolygon(hair, new PointF[] { new PointF(86, 38), new PointF(78, 44), new PointF(79, 76), new PointF(89, 84) });
        using (var hp = new GraphicsPath())
        {
            hp.AddBezier(34, 44, 26, 0, 94, 0, 86, 44);
            hp.AddBezier(86, 44, 80, 30, 40, 30, 34, 44);
            hp.CloseFigure();
            g.FillPath(hair, hp);
        }

        // face
        bool blink = ((int)(t * 10) % 40) == 0;
        if (blink)
        {
            using (var pen = new Pen(ink, 1.8f)) { g.DrawLine(pen, 47, 43, 55, 43); g.DrawLine(pen, 65, 43, 73, 43); }
        }
        else
        {
            g.FillEllipse(ink, 47.5f, 38, 7, 9);
            g.FillEllipse(ink, 65.5f, 38, 7, 9);
            g.FillEllipse(Brushes.White, 51, 39.5f, 2.6f, 2.6f);
            g.FillEllipse(Brushes.White, 69, 39.5f, 2.6f, 2.6f);
        }
        using (var cheek = new SolidBrush(Color.FromArgb(110, 255, 150, 160))) { g.FillEllipse(cheek, 41, 49, 8, 5); g.FillEllipse(cheek, 71, 49, 8, 5); }
        using (var pen = new Pen(Color.FromArgb(190, 90, 100), 1.8f)) g.DrawArc(pen, 54, 49, 12, 8, 20, 140);

        // front arm: swings, or holds the glass
        if (walking)
        {
            Arm(g, top, skin, 79, 78, swing, 75);
        }
        else
        {
            using (var pen = new Pen(topC, 9)) { pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; g.DrawLine(pen, 78, 80, 98, 94); }
            g.FillEllipse(skin, 95, 90, 9, 9);
            using (var gp = new GraphicsPath())
            {
                gp.AddPolygon(new PointF[] { new PointF(94, 70), new PointF(112, 70), new PointF(109, 100), new PointF(97, 100) });
                g.FillPath(new SolidBrush(Color.FromArgb(200, 214, 240, 255)), gp);
                using (var wp = new GraphicsPath())
                {
                    wp.AddPolygon(new PointF[] { new PointF(95.5f, 82), new PointF(110.5f, 82), new PointF(109, 100), new PointF(97, 100) });
                    g.FillPath(new SolidBrush(Color.FromArgb(210, 77, 184, 255)), wp);
                }
                using (var pen = new Pen(Color.FromArgb(90, 174, 232), 2)) g.DrawPath(pen, gp);
            }
            g.FillEllipse(skin, 93, 91, 6, 6);
        }
        g.Restore(st);
    }

    void DrawBubble(Graphics g)
    {
        var r = new Rectangle(bubbleX, 6, 275, 100);
        if (state == State.Talk) r.Height = 100; else r.Height = 70;
        using (var path = Round(r, 16))
        {
            using (var sh = new SolidBrush(Color.FromArgb(40, 0, 0, 0)))
            { var st = g.Save(); g.TranslateTransform(2, 3); g.FillPath(sh, path); g.Restore(st); }
            g.FillPath(Brushes.White, path);
        }
        g.FillPolygon(Brushes.White, new Point[] { new Point(bubbleX + 13, r.Bottom - 2), new Point(bubbleX + 38, r.Bottom - 2), new Point(bubbleX + 6, r.Bottom + 18) });
        var color = Color.FromArgb(34, 51, 68);
        using (var bold = new Font("Segoe UI", 11.5f, FontStyle.Bold))
        using (var norm = new Font("Segoe UI", 10f))
        using (var br = new SolidBrush(color))
        {
            g.DrawString(title, bold, br, new RectangleF(r.X + 14, r.Y + 10, r.Width - 28, 24));
            g.DrawString(sub, norm, br, new RectangleF(r.X + 14, r.Y + 36, r.Width - 28, r.Height - 40));
        }
    }

    void DrawButton(Graphics g, Rectangle r, string text, Color c, bool hot)
    {
        if (hot) c = ControlPaint.Light(c, 0.2f);
        using (var path = Round(r, 19))
        {
            using (var sh = new SolidBrush(Color.FromArgb(60, 0, 0, 0)))
            { var st = g.Save(); g.TranslateTransform(1, 3); g.FillPath(sh, path); g.Restore(st); }
            using (var b = new SolidBrush(c)) g.FillPath(b, path);
        }
        using (var f = new Font("Segoe UI", 10.5f, FontStyle.Bold))
        {
            var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            g.DrawString(text, f, Brushes.White, r, sf);
        }
    }

    void Render()
    {
        using (var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb))
        {
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                if (walkF.Count > 0) DrawSprite(g, state != State.Talk); else DrawGirl(g, state != State.Talk);
                if (state != State.WalkIn) DrawBubble(g);
                if (state == State.Talk)
                {
                    DrawButton(g, btnDrank, "Drank Water!", Color.FromArgb(30, 144, 255), hover == 1);
                    DrawButton(g, btnLater, "Remind Me Later", Color.FromArgb(122, 136, 150), hover == 2);
                }
            }
            Apply(bmp);
        }
    }

    // ---------- per-pixel alpha layered window ----------

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref Point pptDst, ref Size psize, IntPtr hdcSrc, ref Point pprSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hDC);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr hObject);

    void Apply(Bitmap bmp)
    {
        if (!IsHandleCreated) return;
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBmp = IntPtr.Zero, old = IntPtr.Zero;
        try
        {
            hBmp = bmp.GetHbitmap(Color.FromArgb(0));
            old = SelectObject(memDc, hBmp);
            var size = new Size(bmp.Width, bmp.Height);
            var src = new Point(0, 0);
            var top = new Point(Left, Top);
            var blend = new BLENDFUNCTION { BlendOp = 0, BlendFlags = 0, SourceConstantAlpha = 255, AlphaFormat = 1 };
            UpdateLayeredWindow(Handle, screenDc, ref top, ref size, memDc, ref src, 0, ref blend, 2);
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, screenDc);
            if (hBmp != IntPtr.Zero) { SelectObject(memDc, old); DeleteObject(hBmp); }
            DeleteDC(memDc);
        }
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms, System.Drawing

$msg = $env:WATER_MSG
$msg = [regex]::Replace("$msg", "[\uD800-\uDFFF\u2190-\u2BFF\uFE0F]", "").Trim()
if (-not $msg) { $msg = "Time to drink water! Stay hydrated" }
$result = [WaterGirl]::Run($msg, $env:WATER_ASSETS)
Write-Output $result
