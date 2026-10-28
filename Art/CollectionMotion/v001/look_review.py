from build import *
cat=[c for c in json.loads((P/'catalog.json').read_text()) if c['id']!='dusk']
for state in ['look-first','look-second']:
 for page in range(4):
  canvas=Image.new('RGB',(1600,1540),(240,240,240));draw=ImageDraw.Draw(canvas)
  for j,c in enumerate(cat[page*7:page*7+7]):
   im=Image.open(P/c['id']/f'{state}-source.png').convert('RGB');a=np.asarray(im);mask=(a[:,:,1]>30)&((a[:,:,0].astype(int)-a[:,:,1])<160);ys=np.where(mask)[0]
   if len(ys):im=im.crop((0,max(0,int(ys.min())-8),im.width,min(im.height,int(ys.max())+9)))
   im.thumbnail((1600,190));canvas.paste(im,((1600-im.width)//2,j*220+28));draw.text((12,j*220+3),c['id']+' / '+state,font=FONT,fill=INK)
  canvas.save(P/f'qa-{state}-{page}.jpg')
