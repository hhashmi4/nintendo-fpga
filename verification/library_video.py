"""Independent paint-based library specification; no RTL/source introspection."""
from .console_video import PALETTE
from .debug_renderer import FONT_5X8

STAGES = ['WAITING FOR HPS', 'VALIDATING ROM', 'PREPARING CARTRIDGE',
          'LOADING CARTRIDGE', 'READY TO LAUNCH', 'UNSUPPORTED CARTRIDGE',
          'INVALID OR CHANGED ROM', 'FILE OR LIBRARY MISSING',
          'LOAD FAILED - RELOAD REQUIRED', 'INTERRUPTED - RELOAD REQUIRED',
          'RECOVERY - RELOAD REQUIRED', 'GAME ADMITTED']


def library_pixels(packet, status=0x10101, phase=0):
    header=packet & 0xffffffff
    selected=header & 255; total=(header>>8)&511; valid=bool(header & (1<<21))
    event=(header>>17)&3; stage=(header>>22)&15
    state=status & 15
    records=[]
    for i in range(4):
        raw=((packet>>(32+i*224)) & ((1<<224)-1)).to_bytes(28,'little')
        records.append((raw[:24].decode('ascii'),int.from_bytes(raw[24:],'little')))
    meta=records[selected%4][1]; kind=(meta>>24)&3; nes2=bool(meta&(1<<26))
    mapper=meta&255;prg=(meta>>8)&255;chr_=(meta>>16)&255
    pixels=[PALETTE['bg']]*(640*480)
    def rect(x,y,w,h,color):
        for py in range(y,y+h):pixels[py*640+x:py*640+x+w]=[PALETTE[color]]*w
    def text(x,y,line,color='text'):
        for col,char in enumerate(line):
            for gy,row in enumerate(FONT_5X8[char]):
                for gx,bit in enumerate(row):
                    if bit=='1':rect(x+col*16+gx*2,y+gy*2,2,2,color)
    rect(32,128,576,184,'surface');rect(32,96,576,2,'purple');rect(32,96,48,2,'red')
    if valid and total:
        rect(44,176+(selected%4)*32,552,32,'purple');rect(44,176+(selected%4)*32,4,32,'text')
    text(56,40,'NINTENDO FPGA')
    text(56,72,f'GAME LIBRARY   {selected+1 if total else 0:03} / {total:03}','muted')
    text(56,144,'FIRST 256 FILES' if header&(1<<26) else 'YOUR GAMES')
    if not total:
        text(56,184,'NO NES FILES FOUND');text(56,216,'CHECK LIBRARY DIRECTORY','muted')
    elif not valid:text(56,184,'GETTING NEXT PAGE')
    else:
        for i,(title,_) in enumerate(records):
            if selected//4*4+i<total:text(56,184+i*32,title)
    info='METADATA UNAVAILABLE'
    if valid and total and kind and not nes2:info=f'MAPPER {mapper:03}  PRG {prg:03} X16K'
    text(56,336,info,'muted')
    info='PRG BANK 16K / CHR BANK 8K'
    if valid and total and kind:
        info=('NES 2.0 - NOT SUPPORTED' if nes2 else 'CHR RAM 8K / INES 1.0' if not chr_
              else f'CHR ROM {chr_:03} X8K / INES 1.0')
    text(56,360,info,'muted')
    message='WAITING FOR LIBRARY'; color='warning'
    if valid and total:
        if kind==0:message='INVALID ROM - CANNOT LOAD'
        elif kind==1:message='UNSUPPORTED FORMAT' if nes2 else 'UNSUPPORTED MAPPER' if mapper else 'UNSUPPORTED CARTRIDGE'
        elif kind==2:message='SUPPORTED - A OR START';color='success'
        else:message='INVALID METADATA'
    if stage or state in (2,3,6):
        message=STAGES[min(stage,11)];color='text'
        if state==3:message='WAITING FOR GAME FRAME'
        if state==6 and stage<5:message='LOAD ERROR - RELOAD REQUIRED'
        if stage>=5 or state==6:color='error'
    text(56,392,message,color)
    text(56,424,'B BACK / FULL RELOAD TO RETRY' if state in (2,6) else 'UP/DOWN  L/R PAGE  B BACK','muted')
    if state in (2,3) or event==1:
        for i in range(4):rect(536+i*16,144,8,8,'text' if i==phase//8 else 'purple')
    return pixels


def make_packet(titles,metadata,*,selected=0,total=None,stage=0,valid=True,event=0,truncated=False):
    count=len(titles) if total is None else total
    header=selected|(count<<8)|(event<<17)|(1<<19)|(1<<20)|(int(valid)<<21)|(stage<<22)|(int(truncated)<<26)
    raw=b''.join(title.ljust(24).encode('ascii')+meta.to_bytes(4,'little') for title,meta in zip(titles,metadata))
    raw=raw.ljust(112,b'\0')
    return int.from_bytes(raw,'little')<<32|header


def fixtures():
    titles=['SIGNAL TEST','RAM DEMO','MAPPER TWO','LONG TITLE CLIPPED TO ...']
    metadata=[0x02010100,0x02000200,0x01010102,0]
    cases=[(make_packet([],[]),0x10101),
           (make_packet(titles[:1],metadata[:1]),0x10101)]
    cases += [(make_packet(titles,metadata,selected=i),0x10101) for i in range(4)]
    cases += [(make_packet(titles,metadata,selected=4,total=9,valid=False,event=1),0x10101),
              (make_packet(titles,metadata,selected=255,total=256,truncated=True),0x10101)]
    cases += [(make_packet(titles,metadata,stage=i),0x10102 if i<4 else 0x10301 if i==4 else 0x1e006) for i in range(1,11)]
    cases += [(make_packet(['NES TWO'],[0x05000000]),0x10101),
              (make_packet(titles,metadata,stage=4),0x10303)]
    return cases
