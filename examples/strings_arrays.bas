10 dim a(2,3),words$(2)
20 data 001,$d000,"assembly basic"
30 read a$,video,text$
40 words$(1)=text$:a(1,2)=123
50 def fn doubled(x)=x*2
60 print a$;words$(1);fn doubled(a(1,2))
70 print left$(words$(1),8)
80 end
