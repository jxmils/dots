"""Review all collection clips using exactly the exported frame timing."""
from pathlib import Path
from PIL import Image,ImageDraw
from io import BytesIO
from build import P, TIMES, LABELS, FONT, SMALL, BG, INK
import json
catalog=json.loads((P/'catalog.json').read_text())
def save_gif(path, frames, durations):
 buffer=BytesIO()
 frames[0].save(buffer,format='GIF',save_all=True,append_images=frames[1:],duration=durations,loop=0,disposal=2)
 path.write_bytes(buffer.getvalue())
ready=[c for c in catalog if (P/c['id']/'manifest.json').exists() and json.loads((P/c['id']/'manifest.json').read_text())['complete']]
assert len(ready)==29,'Do not label the collection complete until all 29 manifests pass'
config={'characters':[{'id':c['id'],'name':c['name']} for c in ready],'clips':{name:{'title':LABELS[name],'durations':v} for name,v in TIMES.items()}}
html='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Dotlings · all animations</title><style>body{margin:0;background:#f5f2ef;color:#302b2f;font:17px system-ui}main{max-width:1180px;margin:auto;padding:28px}h1{margin:0}header p{color:#726777}nav{display:flex;flex-wrap:wrap;gap:8px;margin:22px 0}button,a{font:inherit}button{border:0;padding:10px 15px;border-radius:20px;background:#e6dfe8;color:#302b2f;cursor:pointer}button[aria-pressed=true]{background:#6b5479;color:white}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px}.pet{background:#ebe6e4;border-radius:24px;text-align:center;padding:4px 12px 16px;overflow:hidden}.pet img{display:block;width:100%;aspect-ratio:384/416;object-fit:contain}.pet h2{font-size:19px;margin:0 0 10px}.pet a{font-size:13px;color:#655071}label{display:inline-flex;align-items:center;gap:10px;margin:0 20px 20px 0}input{accent-color:#6b5479}a{color:#655071}footer{margin:24px 0;font-size:14px}</style><main><header><h1>Every little movement.</h1><p>29 Dotlings · 73 frames each · the complete collection.</p></header><nav id="clips"></nav><label>Speed <input id="speed" type="range" min="0.5" max="2" value="1" step="0.1"><span id="rate">1×</span></label><button id="pause">Pause</button><div class="grid" id="pets"></div><footer><a href="all-dotlings-all-animations.gif">Download the complete collection GIF</a> · <a href="jobs.json">Saved generation prompts</a></footer></main><script>const data=CONFIG;let active='idle',paused=false,offset=0,started=performance.now();const nodes=[],loaded=new Map();for(const pet of data.characters){let card=document.createElement('section');card.className='pet';card.innerHTML=`<img alt="${pet.name}" src="${pet.id}/frames/idle-01.png"><h2>${pet.name}</h2><a href="${pet.id}/all-animations.gif">All movements GIF</a> · <a class="single" href="${pet.id}/gifs/idle.gif">This movement GIF</a>`;document.querySelector('#pets').append(card);nodes.push({pet,image:card.querySelector('img'),link:card.querySelector('.single')})}for(const [key,clip] of Object.entries(data.clips)){let b=document.createElement('button');b.textContent=clip.title;b.dataset.key=key;b.setAttribute('aria-pressed',String(key===active));b.onclick=()=>select(key);document.querySelector('#clips').append(b)}function select(key){active=key;offset=0;started=performance.now();document.querySelectorAll('nav button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.key===key)));for(const n of nodes){n.link.href=`${n.pet.id}/gifs/${key}.gif`;for(let i=0;i<data.clips[key].durations.length;i++){let src=`${n.pet.id}/frames/${key}-${String(i+1).padStart(2,'0')}.png`;if(!loaded.has(src)){let im=new Image();im.src=src;loaded.set(src,im)}}}if(loaded.size>800){for(const [src] of loaded){if(!src.includes('/'+key+'-'))loaded.delete(src)}}}document.querySelector('#pause').onclick=()=>{paused=!paused;if(paused)offset=performance.now()-started;else started=performance.now()-offset;document.querySelector('#pause').textContent=paused?'Play':'Pause'};document.querySelector('#speed').oninput=e=>{document.querySelector('#rate').textContent=e.target.value+'×';started=performance.now();offset=0};function tick(now){let clip=data.clips[active],t=((paused?offset:now-started)/1000*Number(document.querySelector('#speed').value))%clip.durations.reduce((a,b)=>a+b,0),i=0;while(i<clip.durations.length-1&&t>=clip.durations[i])t-=clip.durations[i++];for(const n of nodes){let src=`${n.pet.id}/frames/${active}-${String(i+1).padStart(2,'0')}.png`;if(n.image.getAttribute('src')!==src)n.image.src=src}requestAnimationFrame(tick)}select('idle');requestAnimationFrame(tick);</script></html>'''
(P/'preview.html').write_text(html.replace('CONFIG',json.dumps(config)))
all_frames=[];all_times=[]
for state,times in TIMES.items():
 state_frames=[]
 for i,duration in enumerate(times):
  canvas=Image.new('RGB',(1020,1310),BG);draw=ImageDraw.Draw(canvas)
  draw.text((30,22),'Dotlings · '+LABELS[state],font=FONT,fill=INK)
  for j,c in enumerate(ready):
   x=10+(j%5)*202;y=65+(j//5)*202
   draw.rounded_rectangle((x,y,x+194,y+194),radius=18,fill=(232,227,225))
   im=Image.open(BytesIO((P/c['id']/'frames'/f'{state}-{i+1:02}.png').read_bytes())).convert('RGBA').resize((180,195),Image.Resampling.LANCZOS)
   canvas.paste(im,(x+7,y-17),im);draw.text((x+97,y+178),c['name'],font=SMALL,anchor='mm',fill=INK)
  draw.text((510,1290),'29 companions · 2,117 frames · closed mouths',font=SMALL,anchor='mm',fill=INK)
  state_frames.append(canvas);all_frames.append(canvas);all_times.append(round(duration*1000))
 save_gif(P/f'all-dotlings-{state}.gif',state_frames,[round(t*1000) for t in times])
 print('Collection GIF',state,flush=True)
save_gif(P/'all-dotlings-all-animations.gif',all_frames,all_times)
all_frames[0].save(P/'collection-poster.png')
(P/'collection-manifest.json').write_text(json.dumps({'characters':29,'frames_per_character':73,'total_frames':2117,'states':config['clips'],'characters_detail':config['characters'],'format':'2D sprite playback','generator':'Built-in image_gen','preview':'preview.html','gif':'all-dotlings-all-animations.gif'},indent=2)+'\n')
print('Complete collection gallery and GIFs ready',flush=True)
