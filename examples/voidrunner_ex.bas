1 rem this program expects following
2 rem reservations and the data to
3 rem be externally saved there
4 rem vrasm.bin and sprites.bin
5 rem contain the data
6 rem sprites $3c00 - $3dff
7 rem asm $c000 - $c2ff
10 clr
20 v%=$d000:s%=$0400:c%=$d800:sid%=$d400:hi=0:hu=0
30 dim ex(2),ey(2),ev(2),ea(2),et(2),ed(2),sx(7),sy(7),ss(7),bm(2)
35 bm(0)=2:bm(1)=4:bm(2)=8
40 dim nf(7):nf(0)=4455:nf(1)=5614:nf(2)=6677:nf(3)=8909
50 nf(4)=6677:nf(5)=5614:nf(6)=5001:nf(7)=3746
65 gosub 9920
70 goto 8000
200 j=peek ($dc00):dx=0:dy=0
210 if (j and 1)=0 then dy=-3
220 if (j and 2)=0 then dy=3
230 if (j and 4)=0 then dx=-3
240 if (j and 8)=0 then dx=3
250 px=px+dx:py=py+dy
260 if px<30 then px=30
270 if px>150 then px=150
280 if py<84 then py=84
290 if py>214 then py=214
300 if inv>0 then inv=inv-1
310 co=3:if inv>0 then co=1+(inv and 3)
320 poke v%+39,co
330 cd=cd-1:if cd<0 then cd=0
340 if (j and 16)<>0 or fa=1 or cd>0 then 370
350 fa=1:fx=px+20:fy=py:cd=4:gosub 1500
370 if fa=0 then 400
380 fx=fx+10:if fx>340 then fa=0:poke v%+9,0
400 tm=tm-1:if tm<=0 then gosub 1400
410 for i=0 to 2
420 if ea(i)=0 then 540
430 ex(i)=ex(i)-ev(i)
440 if et(i)=2 then ey(i)=ey(i)+sgn (py-ey(i))
450 if et(i)=3 then ey(i)=ey(i)+ed(i)
460 if ey(i)<85 then ey(i)=85:ed(i)=abs (ed(i))
470 if ey(i)>213 then ey(i)=213:ed(i)=-abs (ed(i))
480 if ex(i)>=15 then 500
490 ea(i)=0:if inv=0 then dm=12:gosub 1600
500 if fa=0 then 520
510 if abs (fx-ex(i))<18 and abs (fy-ey(i))<14 then gosub 1550
520 if ea(i)=0 then 540
530 if abs (px-ex(i))<20 and abs (py-ey(i))<15 then gosub 1650
540 if ea(i)=0 then poke v%+21,peek (v%+21) and (255-bm(i)):goto 560
550 poke v%+2+2*i,ex(i) and 255:poke v%+3+2*i,ey(i)
560 next i
570 if li<1 then 7000
600 if ba=0 then 660
610 bx=bx-3:if bx>=15 then 630
620 ba=0:poke v%+21,peek (v%+21) and 223:goto 660
630 if abs (px-bx)>=18 or abs (py-by)>=16 then 650
640 ba=0:poke v%+21,peek (v%+21) and 223
642 ad=250:gosub 1900:sh=sh+25:if sh>100 then sh=100
645 gosub 1590:gosub 1250
650 if ba=0 then 660
655 poke v%+10,bx and 255:poke v%+11,by
660 if fa=0 then poke v%+9,0
670 if fa=1 then poke v%+8,fx and 255:poke v%+9,fy
680 poke v%,px:poke v%+1,py
690 ws=0:if warp>0 then warp=warp-1:ws=2
695 poke $c218,ws:sys -16384
840 mx=0
850 if ex(0)>255 then mx=mx+2
860 if ex(1)>255 then mx=mx+4
870 if ex(2)>255 then mx=mx+8
880 if fx>255 then mx=mx+16
890 if bx>255 then mx=mx+32
900 poke v%+16,mx
920 get a$:if a$="p" then gosub 1800
930 if a$="q" then li=0
940 if li<1 then 7000
950 goto 200
1000 print chr$ (147);:poke v%+32,6:poke v%+33,0:poke $0286,1
1010 for i=0 to 999:poke c%+i,1:next i
1020 print "score:000000 shield:.......... lives:3"
1030 print "sector:1   kills:000    p=pause q=quit"
1040 print "destroy raiders - collect cyan crystals"
1050 for x=0 to 39:poke s%+120+x,61:poke s%+880+x,61:next x
1060 for x=0 to 39:poke c%+120+x,6:poke c%+880+x,6:next x
1065 for i=0 to 5:poke v%+1+2*i,0:next i
1070 poke v%+21,17:for i=0 to 5:poke v%+1+2*i,0:next i
1080 poke v%+23,0:poke v%+29,0:poke v%+28,47:poke v%+37,1:poke v%+38,7
1090 for i=0 to 5:poke $07f8+i,240+i:next i
1100 poke v%+39,3:poke v%+40,2:poke v%+41,8
1110 poke v%+42,4:poke v%+43,1:poke v%+44,3
1120 px=60:py=150:fa=0:ba=0:fx=0:bx=0:inv=0
1130 sc=0:su=0:sh=100:li=3:lv=1:ki=0:tm=1:cd=0
1135 warp=0
1140 poke $c21d,0:poke $c21e,0
1150 for i=0 to 2:ea(i)=0:ex(i)=0:ey(i)=0:next i
1160 rem rng seeding is dialect specific use its default state
1170 for i=0 to 7
1180 rg=38:gosub 2000:x=1+rr:rg=18:gosub 2000:y=4+rr
1190 rg=2:gosub 2000:z=1+rr:poke $c200+i,x
1192 poke $c208+i,y:poke $c210+i,z:next i
1194 poke $c219,peek ($00a2):poke $c21a,0:poke $c21b,0
1200 gosub 1250
1210 poke sid%+19,5:poke sid%+20,160:poke sid%+14,0
1220 poke sid%+15,6:poke sid%+18,17
1230 poke sid%+23,244:poke sid%+24,31
1240 goto 200
1250 gosub 1920
1260 for j=1 to 6:poke s%+5+j,asc (mid$ (a$,j,1)):next j
1270 n=(sh/10):co=5:if sh<60 then co=7
1280 if sh<30 then co=2
1290 for j=0 to 9:ch=46:if j<n then ch=160
1300 poke s%+20+j,ch:poke c%+20+j,co:next j
1310 poke s%+37,48+li:poke s%+47,48+lv
1320 b$="000"+mid$ (str$ (ki),2):b$=right$ (b$,3)
1330 for j=1 to 3:poke s%+56+j,asc (mid$ (b$,j,1)):next j
1340 return
1400 q=-1
1410 for k=0 to 2:if q=-1 and ea(k)=0 then q=k
1420 next k:if q=-1 then tm=4:return
1430 sb=bm(q):poke v%+21,peek (v%+21) and (255-sb)
1435 ex(q)=330:rg=122:gosub 2000:ey(q)=88+rr
1440 r=rnd (1) and 32767:et(q)=1
1450 if lv>1 and r>14745 then et(q)=2
1460 if lv>3 and r>25559 then et(q)=3
1470 rg=2:gosub 2000:ev(q)=2+rr+(lv-1)/2
1480 rg=2:gosub 2000:ed(q)=1+rr:if (rnd (1) and 32767)<16384 then ed(q)=-ed(q)
1490 poke $07f9+q,240+et(q):co=2
1492 if et(q)=2 then co=8
1494 if et(q)=3 then co=4
1496 poke v%+40+q,co:rg=18:gosub 2000:tm=18+rr-lv
1497 poke v%+2+2*q,ex(q) and 255:poke v%+3+2*q,ey(q)
1498 mx=peek (v%+16) and (255-sb):if ex(q)>255 then mx=mx or sb
1499 poke v%+16,mx:ea(q)=1:poke v%+21,peek (v%+21) or sb:return
1500 poke sid%,80:poke sid%+1,30:poke sid%+5,9
1510 poke sid%+6,200:poke sid%+4,33:poke $c21d,2:return
1550 ad=100*lv:gosub 1900:ki=ki+1:if ki>999 then ki=999
1552 ea(i)=0:fa=0:poke v%+9,0
1560 if ba<>0 or (rnd (1) and 32767)>=7209 then 1570
1562 poke v%+21,peek (v%+21) and 223:bx=ex(i):by=ey(i)
1564 poke v%+10,bx and 255:poke v%+11,by
1566 mx=peek (v%+16) and 223:if bx>255 then mx=mx or 32
1568 poke v%+16,mx:ba=1:poke v%+21,peek (v%+21) or 32
1570 poke sid%+7,40:poke sid%+8,8:poke sid%+12,8
1580 poke sid%+13,160:poke sid%+11,129:poke $c21e,4
1582 nl=1+(ki/12):if nl>9 then nl=9
1584 gosub 1250:if nl>lv then lv=nl:gosub 1700
1585 return
1590 poke sid%,200:poke sid%+1,40:poke sid%+5,9
1592 poke sid%+6,224:poke sid%+4,17:poke $c21d,3:return
1600 sh=sh-dm:inv=18
1610 poke v%+32,2:poke sid%+7,0:poke sid%+8,5
1620 poke sid%+12,5:poke sid%+13,192:poke sid%+11,129:poke $c21e,5
1630 if sh>0 then gosub 1250:poke v%+32,6:return
1640 li=li-1:sh=100:gosub 1250
1645 if li<1 then return
1648 px=60:py=150:poke v%+32,6:return
1650 ea(i)=0:if inv>0 then return
1660 dm=28:gosub 1600:return
1700 ad=500:gosub 1900:warp=50:gosub 1250
1710 poke sid%,0:poke sid%+1,35:poke sid%+5,17
1720 poke sid%+6,240:poke sid%+4,17
1730 for z=0 to 15:poke v%+32,z:poke v%+33,z and 7:next z
1740 poke v%+33,0:poke v%+32,6:poke $c21d,4:return
1800 poke sid%+18,16:poke v%+32,11
1810 get b$:j=peek ($dc00)
1820 if b$="" and (j and 16)<>0 then 1810
1830 poke v%+32,6:poke sid%+18,17:return
1900 sc=sc+ad:if sc>=1000 then sc=sc-1000:su=su+1
1910 if su>999 then su=999:sc=999
1915 return
1920 a$=right$ ("000"+mid$ (str$ (su),2),3)
1930 a$=a$+right$ ("000"+mid$ (str$ (sc),2),3):return
1950 h$=right$ ("000"+mid$ (str$ (hu),2),3)
1960 h$=h$+right$ ("000"+mid$ (str$ (hi),2),3):return
2000 rl=(32767/rg)*rg
2010 rn=rnd (1) and 32767:if rn>=rl then 2010
2020 rr=rn-(rn/rg)*rg:return
7000 poke v%+21,0:poke sid%+18,16
7010 if su>hu or (su=hu and sc>hi) then hu=su:hi=sc
7020 poke sid%+7,0:poke sid%+8,3:poke sid%+12,10
7030 poke sid%+13,240:poke sid%+11,129
7040 print chr$ (147);
7050 print:print:print tab (11)"mission ended"
7055 gosub 1920:gosub 1950
7060 print:print tab (10)"score ";a$
7070 print tab (10)"high  ";h$
7080 print:print tab (5)"fire or space for title"
7085 for z=1 to 80:next z:poke sid%+11,128
7090 j=peek ($dc00):get a$
7100 if (j and 16)=0 or a$=" " then 7120
7110 goto 7090
7120 if (peek ($dc00) and 16)=0 then 7120
7130 goto 8000
8000 poke v%+21,0:for i=0 to 24:poke sid%+i,0:next i
8010 poke sid%+24,15:poke v%+33,0:poke v%+32,6:poke $0286,1
8020 print chr$ (147);
8022 poke $07f8,240:poke $07f9,241:poke v%+21,3
8024 poke v%+28,3:poke v%+29,3:poke v%+23,3
8026 poke v%+37,1:poke v%+38,7:poke v%+39,3:poke v%+40,2
8028 poke v%,80:poke v%+1,190:poke v%+2,4:poke v%+3,190:poke v%+16,2
8030 print:print tab (8)"void runner 64"
8040 print tab (8)"=============="
8050 print:print tab (4)"a deep-space survival shooter"
8060 print:print tab (4)"joystick port 2 to fly and fire"
8070 print tab (4)"destroy raiders, grab crystals"
8080 print tab (4)"p pauses, q aborts mission"
8085 gosub 1950
8090 print:print tab (8)"high score ";h$
8100 print:print tab (5)"press fire or space to launch"
8110 poke sid%+5,17:poke sid%+6,200:poke sid%+4,17:t=0
8120 if (peek ($dc00) and 16)=0 then 8120
8130 t=t+1:if t>=64 then t=0
8132 n=t/8
8140 f=nf(n):poke sid%,f and 255:poke sid%+1,(f/256)
8150 poke v%+32,1+n:poke v%+1,184+2*n:poke v%+3,198-2*n
8155 get a$:j=peek ($dc00)
8160 if (j and 16)=0 or a$=" " then 8180
8170 goto 8130
8180 poke sid%+4,16:poke v%+21,0:goto 1000
9920 for r=0 to 24:a=1024+40*r:poke $c220+r,a and 255
9930 poke $c239+r,(a/256):next r:return