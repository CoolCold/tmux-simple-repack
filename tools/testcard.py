from PIL import Image, ImageDraw
W, H = 240, 150
im = Image.new('RGB', (W, H), 'black'); d = ImageDraw.Draw(im)
bars = [(255,255,255),(255,255,0),(0,255,255),(0,255,0),(255,0,255),(255,0,0),(0,0,255),(40,40,40)]
for i, c in enumerate(bars): d.rectangle([i*W//8, 0, (i+1)*W//8-1, 89], fill=c)
for x in range(W): d.line([x, 90, x, 119], fill=(x*255//W,)*3)
for x in range(0, W, 20): d.line([x, 120, x, H-1], fill=(80,80,80))
d.rectangle([0, 0, W-1, H-1], outline=(255,128,0), width=2)
d.text((8, 128), f"sixel test card {W}x{H}px", fill=(255,255,255))
import sys; im.save(sys.argv[1] if len(sys.argv) > 1 else 'card.png')
