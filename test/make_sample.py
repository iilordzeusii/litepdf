# pip install reportlab pillow ; writes test/sample.pdf (3 pages, image, form fields, a fake secret)
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from PIL import Image
Image.effect_noise((2400, 1800), 60).convert("RGB").save("test/noise.jpg", quality=95)
c = canvas.Canvas("test/sample.pdf", pagesize=A4)
c.drawString(72, 780, "Page one. Confidential account SECRET-1234 belongs to Alice.")
c.drawString(72, 760, "Public sentence that must survive redaction.")
c.drawImage("test/noise.jpg", 72, 400, 400, 300)
c.acroForm.textfield(name="fullname", x=72, y=340, width=200, height=20, value="")
c.acroForm.checkbox(name="agree", x=72, y=300, size=16)
c.showPage(); c.drawString(72, 780, "Page two. Another line."); c.showPage(); c.drawString(72, 780, "Page three. Last."); c.save()
