"""Build reference-preserving collection motion strips and their review GIFs.
Generated art is never drawn or distorted here: only matte extraction, uniform
scaling, registration, optional symmetric mirroring, and packing are performed.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps
import numpy as np
import json, argparse, hashlib
P=Path(__file__).resolve().parent; ROOT=P.parents[2]
COUNTS={'idle':6,'move-right':8,'wave':4,'hop':5,'disappointed':8,'waiting':6,'thinking':6,'reviewing':6,'look-first':8,'look-second':8}
NAMES={'idle':'Idle','move-right':'MoveRight','move-left':'MoveLeft','wave':'Wave','hop':'Jump','disappointed':'Disappointed','waiting':'Waiting','thinking':'Thinking','reviewing':'Reviewing','look-around':'LookAround'}
TIMES={'idle':[1.25,.5,.07,.07,.11,1.2],'move-right':[.16]*8,'move-left':[.16]*8,'wave':[1.25,.18,.45,1.32],'hop':[1.5,.13,.15,.15,1.27],'disappointed':[.7,.35,.2,.25,.45,.2,.35,.7],'waiting':[.65,.5,.18,.5,.5,.67],'thinking':[.65,.5,.25,.18,.7,.72],'reviewing':[.6,.5,.5,.18,.62,.6],'look-around':[.2]*16}
LABELS={'idle':'Idle / blink','move-right':'Move right','move-left':'Move left','wave':'Wave','hop':'Little hop','disappointed':'Disappointed','waiting':'Waiting','thinking':'Thinking','reviewing':'Look closely','look-around':'Look around'}
FONT=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',20)
SMALL=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',15)
BG=(245,242,239);INK=(48,43,47)

def extract(path,count):
 rgb=np.asarray(Image.open(path).convert('RGB')).astype(float)
 # A few generator exports include a white canvas border, outside the magenta
 # artwork. Trim only uninterrupted near-white edge rows/columns before keying.
 magenta=(rgb[:,:,0]>180)&(rgb[:,:,2]>180)&(rgb[:,:,1]<80)
 rows=np.where(magenta.mean(axis=1)>.95)[0]
 assert len(rows),(path,'missing clean magenta margin')
 rgb=rgb[rows[0]:rows[-1]+1]
 key=np.median(np.concatenate([rgb[:30].reshape(-1,3),rgb[-30:].reshape(-1,3)]),axis=0)
 strength=min(key[0]-key[1],key[2]-key[1]);assert strength>100,(path,'not a magenta backdrop')
 raw=1-np.clip(np.minimum(rgb[:,:,0]-rgb[:,:,1],rgb[:,:,2]-rgb[:,:,1])/strength,0,1)
 # Interior coloured fur must stay opaque; apply the key matte only at the edge.
 interior=np.asarray(Image.fromarray(((raw>.58)*255).astype('uint8')).filter(ImageFilter.MinFilter(5)))>0
 alpha=np.where(interior,1,raw);alpha[alpha<.05]=0
 fg=np.clip((rgb-(1-alpha[:,:,None])*key)/np.maximum(alpha[:,:,None],.001),0,255)
 rgba=np.dstack([fg,alpha*255]).astype('uint8');rgba[alpha==0,:3]=0
 cols=np.sum(alpha>.65,axis=0)>2;d=np.diff(np.pad(cols.astype(int),(1,1)))
 runs=[(a,b) for a,b in zip(np.where(d==1)[0],np.where(d==-1)[0]) if b-a>8]
 assert len(runs)==count,(path.name,'pose count',len(runs),'expected',count,runs)
 boxes=[]
 for l,r in runs:
  ys,_=np.where(alpha[:,l:r]>.25)
  boxes.append((max(0,int(l)-2),max(0,int(ys.min())-2),min(rgb.shape[1],int(r)+2),min(rgb.shape[0],int(ys.max())+3)))
 return alpha,rgba,boxes

def build(c,partial=False,export=False):
 d=P/c['id'];(d/'frames').mkdir(exist_ok=True);(d/'gifs').mkdir(exist_ok=True)
 if c['id']=='dusk':
  old=ROOT/'Art/Dusk/SpritePreview/complete-v001'
  frames={name:[Image.open(f).convert('RGBA') for f in sorted((old/'frames').glob(name+'-*.png'))] for name in COUNTS}
  frames['move-left']=[Image.open(f).convert('RGBA') for f in sorted((old/'frames').glob('move-left-*.png'))]
  metadata={'source':'Retained approved Dusk complete-v001 frames'}
 else:
  raw={};metadata={};frames={}
  for name,count in {**COUNTS,**({'move-left':8} if (d/'move-left-source.png').exists() else {})}.items():
   path=d/f'{name}-source.png'
   if not path.exists():
    if partial:continue
    raise ValueError(f'{c["id"]}/{name} missing')
   raw[name]=extract(path,count)
  if not raw:return False
  reference=Image.open(d/'reference.png').convert('RGBA');bbox=reference.getbbox();rw=bbox[2]-bbox[0];rh=bbox[3]-bbox[1]
  target_height=min(250,330*rh/rw)
  look_heights=[b[3]-b[1] for name,(_,_,boxes) in raw.items() if name.startswith('look-') for b in boxes]
  for name,(alpha,rgba,boxes) in raw.items():
   selected=[boxes[0],boxes[-1]] if name=='hop' else boxes
   h=np.median([b[3]-b[1] for b in selected])
   if name.startswith('look-'):h=np.median(look_heights)
   scale=min(target_height/h,330/max(b[2]-b[0] for b in boxes))
   restbase=np.median([b[3] for b in selected]);out=[]
   for i,(x0,y0,x1,y1) in enumerate(boxes):
    region=alpha[y0+int((y1-y0)*.72):y1,x0:x1];weights=region.sum(axis=0)
    cx=x0+float(np.dot(np.arange(len(weights)),weights)/weights.sum())
    crop=Image.fromarray(rgba[y0:y1,x0:x1]).resize((round((x1-x0)*scale),round((y1-y0)*scale)),Image.Resampling.LANCZOS)
    bottom=365+(y1-restbase)*scale if name=='hop' else 365
    x=round(192-(cx-x0)*scale);y=round(bottom-crop.height)
    x=max(8,min(376-crop.width,x))
    assert y>=0 and y+crop.height<=416,(c['id'],name,i,'vertical crop',y,crop.size)
    cell=Image.new('RGBA',(384,416));cell.alpha_composite(crop,(x,y));out.append(cell)
   frames[name]=out;metadata[name]={'scale':scale,'bounds':boxes,'source_sha256':hashlib.sha256((d/f'{name}-source.png').read_bytes()).hexdigest()}
  if 'move-right' in frames and 'move-left' not in frames:
   # Explicit left poses are required for the asymmetrical designs in jobs.json.
   needs_left=any(j['id']==c['id'] and j['state']=='move-left' for j in json.loads((P/'jobs.json').read_text()))
   if not needs_left:frames['move-left']=[ImageOps.mirror(im) for im in frames['move-right']]
 if 'look-first' in frames and 'look-second' in frames:
  frames['look-around']=frames['look-first']+frames['look-second']
  frames['cardinals']=[frames['look-around'][i] for i in [0,4,8,12]]
 for name,ims in frames.items():
  for i,im in enumerate(ims):im.save(d/'frames'/f'{name}-{i+1:02}.png')
 for name,times in TIMES.items():
  if name not in frames:continue
  ims=[]
  for im in frames[name]:
   canvas=Image.new('RGB',(384,446),BG);canvas.paste(im,(0,0),im)
   ImageDraw.Draw(canvas).text((192,423),c['name']+' · '+LABELS[name],font=SMALL,anchor='mm',fill=INK);ims.append(canvas)
  ims[0].save(d/'gifs'/f'{name}.gif',save_all=True,append_images=ims[1:],duration=[round(v*1000) for v in times],loop=0,disposal=2)
 complete=all(name in frames for name in TIMES)
 if complete:
  anchors=[]
  for im in frames['cardinals']:
   canvas=Image.new('RGB',(384,446),BG);canvas.paste(im,(0,0),im)
   ImageDraw.Draw(canvas).text((192,423),c['name']+' · Up / right / down / left',font=SMALL,anchor='mm',fill=INK)
   anchors.append(canvas)
  anchors[0].save(d/'gifs/cardinals.gif',save_all=True,append_images=anchors[1:],duration=800,loop=0,disposal=2)
  assert sum(len(frames[n]) for n in TIMES)==73
  # Dedicated strips avoid decoding a giant atlas for each small reaction.
  for name,suffix in NAMES.items():
   strip=Image.new('RGBA',(384*len(frames[name]),416))
   for i,im in enumerate(frames[name]):strip.alpha_composite(im,(384*i,0))
   strip.save(d/f'{name}-strip.png')
   if export and c['id']!='dusk':
    strip.save(ROOT/'Resources'/f'Companion{c["id"].capitalize()}Motion{suffix}.png')
  overview=[]
  for f in range(80):
   canvas=Image.new('RGB',(960,1220),BG);draw=ImageDraw.Draw(canvas)
   draw.text((30,25),c['name']+' · complete animation set',font=FONT,fill=INK)
   for j,name in enumerate(TIMES):
    x=20+(j%3)*310 if j<9 else 20;y=70+(j//3)*280 if j<9 else 910;w=300 if j<9 else 920
    draw.rounded_rectangle((x,y,x+w,y+270),radius=20,fill=(232,227,225))
    t=(f/25)%sum(TIMES[name]);idx=min(len(TIMES[name])-1,int(np.searchsorted(np.cumsum(TIMES[name]),t,side='right')))
    im=frames[name][idx].resize((254,275),Image.Resampling.LANCZOS);canvas.paste(im,(x+(w-254)//2,y-15),im)
    draw.text((x+w/2,y+245),LABELS[name],font=SMALL,anchor='mm',fill=INK)
   draw.text((480,1200),'73 sprite frames · closed mouths',font=SMALL,anchor='mm',fill=INK);overview.append(canvas)
  overview[0].save(d/'all-animations.gif',save_all=True,append_images=overview[1:],duration=40,loop=0,disposal=2)
  overview[0].save(d/'poster.png')
 receipt={'id':c['id'],'name':c['name'],'complete':complete,'frames':sum(len(frames[n]) for n in TIMES if n in frames),'states':{n:len(frames[n]) for n in TIMES if n in frames},'metadata':metadata,'app_exported':complete and export}
 (d/'manifest.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print(c['id'],receipt['frames'],'frames', 'complete' if complete else 'partial',flush=True)
 return complete

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--ids',nargs='*');ap.add_argument('--partial',action='store_true');ap.add_argument('--export-app',action='store_true');ap.add_argument('--workers',type=int,default=1);args=ap.parse_args()
 catalog=json.loads((P/'catalog.json').read_text());failures=[]
 catalog=[c for c in catalog if not args.ids or c['id'] in args.ids]
 from concurrent.futures import ProcessPoolExecutor, as_completed
 with ProcessPoolExecutor(max_workers=max(1,args.workers)) as pool:
  pending={pool.submit(build,c,args.partial,args.export_app):c for c in catalog}
  for result in as_completed(pending):
   c=pending[result]
   try:result.result()
   except Exception as e:failures.append({'id':c['id'],'error':str(e)});print('ERROR',c['id'],e,flush=True)
 (P/'last-build-errors.json').write_text(json.dumps(failures,indent=2)+'\n')
 if failures:raise SystemExit(1)
