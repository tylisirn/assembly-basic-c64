10 u%=65535:s=u%:v%=s
20 print "unsigned ";u%;"signed ";s;"round trip ";v%
30 d%=2:print "unsigned division ";u%/d%
40 print "mixed division ";u%/2
50 dim a%(1):a%(0)=32768:a%(1)=65535
60 print "array ";a%(0);a%(1)
70 for i%=32766 to 32769:print i%;:next i%:print
80 f%=fre():print "free basic bytes ";f%
90 print "fre preserves values ";u%;a%(1)
