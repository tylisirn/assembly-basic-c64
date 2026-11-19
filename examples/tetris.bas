10 rem tetris for assembly basic on the c64
20 rem board is poked into screen ram $0400 and colour ram $d800
30 rem pieces are 16-bit masks of a 4x4 grid, held in unsigned words
40 rem no sprites, so no reserve is needed: screen and colour ram are fixed
100 dim pc%(27),ko(4),pcol(6),sp%(4),b(199),rf(19)
110 jy%=$dc00:ob%=1119:ko(1)=-1:ko(2)=1:ko(3)=-2:ko(4)=2
120 for i=0 to 27:read pc%(i):next i
130 for i=0 to 6:read pcol(i):next i
140 for i=0 to 4:read sp%(i):next i
150 def fn mod7(x)=x-(x/7)*7
200 poke $d020,0:poke $d021,0:poke 646,1
205 print chr$(147);
210 for y=0 to 19:w%=1024+(y+2)*40+14
220 poke w%,160:poke w%+11,160:w%=w%+$d400:poke w%,12:poke w%+11,12
230 next y
240 for x=0 to 11:w%=1918+x:poke w%,160:poke w%+$d400,12:next x
250 tr=0:tc=17:t$="tetris":gosub 8000
260 tr=3:tc=1:t$="score":gosub 8000
270 tr=6:tc=1:t$="best":gosub 8000
280 tr=9:tc=1:t$="lines":gosub 8000
290 tr=12:tc=1:t$="level":gosub 8000
300 tr=3:tc=31:t$="next":gosub 8000
310 tr=11:tc=31:t$="port 2":gosub 8000
320 tr=13:tc=31:t$="l/r move":gosub 8000
330 tr=14:tc=31:t$="up: cw":gosub 8000
340 tr=15:tc=31:t$="dn: ccw":gosub 8000
350 tr=16:tc=31:t$="fire:drop":gosub 8000
360 gosub 7000:gosub 8200
370 tr=10:tc=14:t$="press fire":gosub 8000:gosub 9500
400 rem new game
410 for i=0 to 199:b(i)=0:next i
420 sc%=0:nl=0:lv=0:dl=40:gosub 7000:gosub 8200
430 pt=9:gosub 3600:pj=not peek(jy%) and 31
600 gosub 3500:if ok=0 then 900
610 gx=px:gy=py:gr=pr:gt=pt:gc=pcol(pt):gosub 3000
700 j=not peek(jy%) and 31:e=j and not pj:pj=j
710 qx=px:qy=py:qr=pr:lk=0
720 if e and 1 then rd=1:gosub 4000
730 if e and 2 then rd=3:gosub 4000
740 hd=j and 12:if hd=0 then 800
750 if e and 12 then mt=ti+8:goto 770
760 if ti-mt<0 then 800
765 mt=ti+3
770 dx=0:if hd and 4 then dx=-1
780 if hd and 8 then dx=1
790 px=px+dx:gosub 1000:if ok=0 then px=px-dx
800 if e and 16 then gosub 4500:lk=-1
810 if ti-tm<dl then 820
815 tm=ti:py=py+1:gosub 1000:if ok=0 then py=py-1:lk=-1
820 if px<>qx or py<>qy or pr<>qr then gosub 3200
830 if lk=0 then 700
840 gosub 5000:gosub 6000:gosub 8200:goto 600
900 gosub 8200
910 tr=10:tc=14:t$="game over":gosub 8000
920 dt=ti
930 if ti-dt<90 then 930
940 gosub 9500:goto 400
1000 rem fit test: uses px,py,pr,pt; returns ok=-1 if piece fits
1005 m%=pc%(pt*4+pr):ok=-1
1010 for i=0 to 15
1020 if ((m%>>(15-i)) and 1)=0 then 1070
1030 fx=px+(i and 3):fy=py+(i>>2)
1040 if fx<0 or fx>9 or fy>19 then ok=0:goto 1070
1050 if fy<0 then 1070
1060 if b(fy*10+fx)<>0 then ok=0
1070 next i
1080 return
2000 rem draw one cell: cx,cy,cc (cc=0 erases), base address ob%
2005 if cy<0 then return
2010 a%=ob%+cy*40+cx
2020 if cc=0 then poke a%,32:return
2025 poke a%,160:poke a%+$d400,cc
2030 return
3000 rem draw piece gt at gx,gy rotation gr in colour gc
3005 m%=pc%(gt*4+gr)
3010 for i=0 to 15
3020 if ((m%>>(15-i)) and 1)=0 then 3040
3030 cx=gx+(i and 3):cy=gy+(i>>2):cc=gc:gosub 2000
3040 next i
3050 return
3200 rem erase old position, draw new
3210 gx=qx:gy=qy:gr=qr:gt=pt:gc=0:gosub 3000
3220 gx=px:gy=py:gr=pr:gc=pcol(pt):gosub 3000
3230 return
3500 rem spawn: current=next, pick new next, show preview
3510 pt=nx:gosub 3600:px=3:py=0:pr=0:tm=ti
3520 gosub 3700:gosub 1000
3530 return
3600 rem pick random next piece (reroll once on repeat)
3610 v=(rnd(1)>>8) and 255:q=fn mod7(v)
3620 if q=pt then v=(rnd(1)>>8) and 255:q=fn mod7(v)
3630 nx=q:return
3700 rem draw next-piece preview
3710 ob%=1255
3720 for i=0 to 15:cx=i and 3:cy=i>>2:cc=0:gosub 2000:next i
3730 gx=0:gy=0:gr=0:gt=nx:gc=pcol(nx):gosub 3000
3740 ob%=1119:return
4000 rem rotate by rd (1=cw 3=ccw) with simple wall kicks
4010 qx=px:qr=pr:pr=(pr+rd) and 3:dn=0
4020 for k=0 to 4
4030 px=qx+ko(k):gosub 1000
4040 if ok and dn=0 then dn=1:kx=px
4050 next k
4060 if dn then px=kx else px=qx:pr=qr
4070 return
4500 rem hard drop
4510 cn=0
4520 py=py+1:gosub 1000
4530 if ok then cn=cn+1:goto 4520
4540 py=py-1:ps=cn*2:gosub 8300:return
5000 rem lock piece into board
5010 m%=pc%(pt*4+pr)
5020 for i=0 to 15
5030 if ((m%>>(15-i)) and 1)=0 then 5060
5040 fy=py+(i>>2):fx=px+(i and 3)
5050 if fy>=0 then b(fy*10+fx)=pcol(pt)
5060 next i
5070 return
6000 rem find and clear full rows, score, level
6010 lc=0
6020 for fy=0 to 19:f=-1
6030 for fx=0 to 9:if b(fy*10+fx)=0 then f=0
6040 next fx
6050 rf(fy)=f:if f=0 then 6090
6060 lc=lc+1
6070 for fx=0 to 9:cx=fx:cy=fy:cc=1:gosub 2000:next fx
6090 next fy
6100 if lc=0 then return
6110 dt=ti
6120 if ti-dt<12 then 6120
6130 dst=19
6140 for sr=19 to 0 step -1
6150 if rf(sr)<>0 then 6190
6160 if dst=sr then 6180
6170 for fx=0 to 9:b(dst*10+fx)=b(sr*10+fx):next fx
6180 dst=dst-1
6190 next sr
6200 for fy=0 to dst:for fx=0 to 9:b(fy*10+fx)=0:next fx:next fy
6210 gosub 7000
6220 ps=sp%(lc)*(lv+1):gosub 8300
6230 nl=nl+lc:lv=nl/10:if lv>9 then lv=9
6240 dl=40-lv*4:return
7000 rem redraw whole board
7010 ob%=1119
7020 for fy=0 to 19:for fx=0 to 9
7030 cx=fx:cy=fy:cc=b(fy*10+fx):gosub 2000
7040 next fx:next fy
7050 return
8000 rem print text t$ at row tr, column tc by poking screen codes
8010 sa%=1024+tr*40+tc
8020 for i=1 to len(t$)
8030 c=asc(mid$(t$,i,1)):if c>64 then c=c and 31
8040 da%=sa%+i-1:poke da%,c:poke da%+$d400,1
8050 next i
8060 return
8100 rem print number nv% right-aligned in 6 columns
8110 t$=right$("      "+str$(nv%),6):gosub 8000:return
8200 rem refresh score, best, lines, level
8210 nv%=sc%:tr=4:tc=1:gosub 8100
8220 nv%=hi%:tr=7:tc=1:gosub 8100
8230 nv%=nl:tr=10:tc=1:gosub 8100
8240 nv%=lv+1:tr=13:tc=1:gosub 8100
8250 return
8300 rem add ps to score (clamped at 65535) and track best
8310 os%=sc%:sc%=sc%+ps:if sc%<os% then sc%=65535
8320 if sc%>hi% then hi%=sc%
8330 return
9500 rem wait for fire release, then fire press
9510 if (peek(jy%) and 16)=0 then 9510
9520 if peek(jy%) and 16 then 9520
9530 return
9800 data $0f00,$2222,$00f0,$4444
9810 data $0660,$0660,$0660,$0660
9820 data $4e00,$4640,$0e40,$4c40
9830 data $6c00,$4620,$06c0,$8c40
9840 data $c600,$2640,$0c60,$4c80
9850 data $8e00,$6440,$0e20,$44c0
9860 data $2e00,$4460,$0e80,$c440
9870 data 3,7,4,5,2,6,8
9880 data 0,40,100,300,1200
