from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json
p=Path(__file__).resolve().parent
root=p.parents[2]
base=[{'id':'lavender','name':'Lilac','file':'Resources/CompanionAtlas.png','identity':'Lavender pear-shaped mochi with small curled crest and two petal-like side nubs'}, {'id':'blue','name':'Sky','file':'Resources/CompanionBlueAtlas.png','identity':'Sky-blue rounded pear with a curved top curl and short attached side arms'}, {'id':'pillow','name':'Cloud','file':'Resources/CompanionPillowAtlas.png','identity':'Very wide sky-blue rounded pillow, three small tufts, short side arms, smooth flat bottom without feet'}]
for f in ['collection-prompts.json','extra-creatures-prompts.json']:
 for c in json.loads((root/'docs'/f).read_text())['creatures']:
  c['identity']=c['prompt'].split('New character: ')[-1];base.append(c)
assert len(base)==29
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',22)
for offset in range(0,len(base),10):
 sheet=Image.new('RGB',(1000,480),(245,242,239));draw=ImageDraw.Draw(sheet)
 for j,c in enumerate(base[offset:offset+10]):
  d=p/c['id'];d.mkdir(exist_ok=True)
  im=Image.open(root/c['file']).convert('RGBA');canonical=im.crop((0,0,im.width//3,im.height//2));canonical.save(d/'reference.png')
  thumb=canonical.resize((200,200));x=j%5*200;y=j//5*240
  sheet.paste(thumb,(x,y),thumb);draw.text((x+100,y+213),c['name'],font=font,anchor='mm',fill=(40,35,45))
  c['reference']=str(d/'reference.png');c['original_reference']=str(root/c['file'])
 sheet.save(p/f'references-{offset//10+1}.png')
(p/'catalog.json').write_text(json.dumps(base,indent=2)+'\n')
print('Prepared',len(base),'identity references')
