"""Render the documented baseline architecture as standalone PNG diagrams."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/images'
FONT=Path('C:/Windows/Fonts/msyh.ttc')
if not FONT.exists():
    raise SystemExit('Set FONT in this optional drawing script to a Chinese-capable font.')

class Drawing:
    def __init__(self,w,h):
        self.im=Image.new('RGB',(w,h),'white')
        self.d=ImageDraw.Draw(self.im)
        self.fonts={s:ImageFont.truetype(str(FONT),s) for s in (20,23,26,30,34,40)}
    def text(self,xy,text,size=26,fill='#202932',center=False):
        font=self.fonts[size]
        self.d.multiline_text(xy,text,font=font,fill=fill,spacing=8,anchor='mm' if center else 'la',align='center' if center else 'left')
    def box(self,rect,text,fill='white',size=26):
        self.d.rectangle(rect,fill=fill,outline='#344450',width=2)
        self.text(((rect[0]+rect[2])/2,(rect[1]+rect[3])/2),text,size,center=True)
    def group(self,rect,title,fill):
        self.d.rectangle(rect,fill=fill,outline='#a2b1bd',width=2)
        self.text((rect[0]+18,rect[1]+12),title,26)
    def arrow(self,points,dashed=False,fill='#344450'):
        for a,b in zip(points,points[1:]):
            if dashed:
                length=math.dist(a,b)
                for i in range(0,int(length),18):
                    lo=i/max(length,1); hi=min(i+10,length)/max(length,1)
                    self.d.line([(a[0]+(b[0]-a[0])*lo,a[1]+(b[1]-a[1])*lo),(a[0]+(b[0]-a[0])*hi,a[1]+(b[1]-a[1])*hi)],fill=fill,width=3)
            else: self.d.line([a,b],fill=fill,width=3)
        a,b=points[-2:]; angle=math.atan2(b[1]-a[1],b[0]-a[0]); length=14
        self.d.polygon([b,(b[0]-length*math.cos(angle-.45),b[1]-length*math.sin(angle-.45)),(b[0]-length*math.cos(angle+.45),b[1]-length*math.sin(angle+.45))],fill=fill)
    def save(self,name):
        OUT.mkdir(exist_ok=True,parents=True); self.im.save(OUT/name)

def hardware():
    p=Drawing(1800,2260)
    p.text((65,32),'INT8 Transformer 加速器 v0.1 · 硬件数据通路',40)
    p.text((65,96),'默认 N=4 / D=8 / F=16 / LANES=2；单时钟、整批计算、PE 时分复用',26)
    p.text((65,140),'逻辑规格：2 路18×18乘积 + 64位累加；矩阵存储752 B；实际PPA待DC/ICC',23,fill='#5b6873')
    p.group((50,215,1165,635),'① 输入、权重和结果存储 · transformer_top', '#e7f0fa')
    p.box((85,290,370,405),'主机写接口\nwr_en / bank / addr\nwr_data：signed 8 bit',size=23)
    p.box((445,285,1125,405),'输入 X[N,D] + 权重 Wq / Wk / Wv / W1 / W2\n每元素 signed 8 bit；按行主序存储',size=26)
    p.arrow([(370,347),(445,347)])
    p.box((445,460,1125,580),'中间值 Q / K / V / score / Context / H / Y：8 bit\n概率 P[N,N]：unsigned 16 bit（raw / 32768）',size=23)
    p.text((85,465),'共14个矩阵数组\n默认752 B\n寄存器存储基线\n无BRAM/SRAM宏',23)
    p.group((50,710,1165,1215),'② 唯一一套共享点积引擎 · PE + 累加 + 量化', '#fdf2cf')
    p.box((95,785,1125,875),'操作数选择器：case(phase) + row / col / pos\n每路 aa / bb：signed 18 bit；不足 LANES 的尾部补0',size=26)
    p.box((100,950,400,1060),'pe_array\n2 路18×18乘法\n乘积36位 → 归约64位',size=23)
    p.box((465,950,755,1060),'accumulator：64 bit\ntotal = 旧和 + 本组和\n每个输出元素完成后清0',size=23)
    p.box((820,950,1120,1060),'phase选择后处理\n缩放 / 右移 / sat8\nFF1额外执行ReLU',size=23)
    p.arrow([(250,875),(250,950)]); p.arrow([(400,1005),(465,1005)]); p.arrow([(755,1005),(820,1005)])
    p.arrow([(970,1060),(970,1140),(1140,1140),(1140,605),(1040,605),(1040,580)])
    p.text((740,1152),'元素完成时写回对应数组',23)
    p.arrow([(650,580),(650,785)])
    p.text((665,650),'组合读 → 选两组元素',23)
    p.group((50,1295,1165,1735),'③ 专用逐行 Softmax · softmax_unit / exp_lut', '#e7f3e4')
    p.box((85,1375,365,1500),'第1遍：找行最大值\nlogit：signed 8 bit\nmaximum：signed 9 bit',size=23)
    p.box((430,1375,735,1500),'第2遍：指数查表并求和\nLUT：256项 × 17 bit\ndenominator：32 bit',size=23)
    p.box((800,1375,1120,1500),'第3遍：归一化除法\n(e << 15) / sum(e)\nprob：unsigned 16 bit',size=23)
    p.arrow([(365,1437),(430,1437)]); p.arrow([(735,1437),(800,1437)])
    p.text((90,1560),'三遍均从顶层 score 组合读取；指数是查表组合输出，不是流水BRAM。',23)
    p.text((90,1608),'最后一遍 valid / index / prob 回写 P；done 表示一行结束。',23)
    p.text((90,1656),'每行 N+N+N 拍；除法当前为组合路径，真实面积和时序仍待测。',23)
    p.arrow([(500,580),(500,610),(15,610),(15,1265),(220,1265),(220,1375)])
    p.text((58,1238),'score → logit',23)
    p.arrow([(1120,1440),(1195,1440),(1195,520),(1125,520)])
    p.text((810,1250),'prob → P（独立回写路径）',23)
    p.group((50,1810,1165,2050),'④ 主机读回与完成握手', '#f9e4e4')
    p.box((90,1880,1120,2000),'rd_bank / rd_addr → 组合读选择器 → rd_data：32 bit\n八个bank可观测Y/Q/K/V/score/P/Context/H；done后读取最终结果',size=26)
    p.arrow([(550,580),(550,625),(30,625),(30,1940),(90,1940)])
    p.group((1245,215,1750,785),'⑤ 控制器 · 顶层真实状态', '#eee9f7')
    p.box((1280,285,1715,395),'IDLE → MAC\nSM_START → SM_WAIT\n完成后回IDLE，done单拍',size=26)
    p.text((1280,438),'state：决定工作模式\nphase：决定复用的运算\nrow / col：输出元素坐标\npos：点积归约起始项\ncycles：仅计算拍数\nbusy = state != IDLE',26)
    p.arrow([(1245,695),(1175,695),(1175,830),(1125,830)],True,fill='#795b99')
    p.arrow([(1280,735),(1220,735),(1220,1550),(1165,1550)],True,fill='#795b99')
    p.group((1245,855,1750,1980),'⑥ 运算调度 · 共享PE复用', '#e7f2f2')
    stages=[('phase 0：Q = X × Wq','8 bit · N×D'),('phase 1：K = X × Wk','8 bit · N×D'),('phase 2：V = X × Wv','8 bit · N×D'),('phase 3：score = Q × transpose(K)','缩放 + sat8 · N×N'),('专用状态：逐行Softmax','P：16 bit · N×N'),('phase 4：Context = P × V','8 bit · N×D'),('phase 5：H = ReLU(C × W1)','8 bit · N×F'),('phase 6：Y = H × W2','8 bit · N×D')]
    for i,(a,b) in enumerate(stages):
        y=930+i*122
        p.box((1275,y,1720,y+92),a+'\n'+b,size=23)
        if i<7:p.arrow([(1497,y+92),(1497,y+122)])
    p.text((65,2100),'实线：数据依赖 / 读写路径；紫色虚线：控制。框内标的是逻辑规格，不是工具资源报告。',23)
    p.text((65,2150),'默认事务：1080 计算拍；主机加载和读回不计入。外部接口没有 ready/valid 流式背压。',23)
    p.save('transformer_hardware.png')

def fsm():
    p=Drawing(1700,1260)
    p.text((55,30),'控制与握手 · 对照真实 state / phase',40)
    p.group((45,115,820,1160),'顶层 transformer_top.state', '#e7f0fa')
    for rect,text in [((180,195,680,300),'IDLE (0)\n加载矩阵；start && !wr_en接收启动'),((180,420,680,540),'MAC (1)\n完成点积 → 换列 → 换行 → 换phase'),((180,690,680,795),'SM_START (2)\nSoftmax start拉高一拍'),((180,920,680,1045),'SM_WAIT (3)\nsm_valid写P；sm_done推进下一行')]:p.box(rect,text,size=23)
    p.arrow([(430,300),(430,420)]);p.text((445,345),'phase=0',23)
    p.arrow([(430,540),(430,690)]);p.text((445,590),'phase3全部完成',23)
    p.arrow([(430,795),(430,920)])
    p.arrow([(180,980),(100,980),(100,740),(180,740)]);p.text((53,825),'下一行',20)
    p.arrow([(680,980),(755,980),(755,480),(680,480)]);p.text((590,835),'最后一行：phase=4',20)
    p.arrow([(180,465),(70,465),(70,245),(180,245)]);p.text((85,325),'phase6结束\ndone=1',20)
    p.group((890,115,1650,1160),'子模块 softmax_unit.state', '#e7f3e4')
    for rect,text in [((1010,195,1530,300),'0：空闲\nstart后清指针、最大值、分母'),((1010,420,1530,540),'1：扫描最大值\nN拍；行末ptr归0'),((1010,690,1530,795),'2：扫描指数和\nN拍；LUT查表并累加'),((1010,920,1530,1045),'3：扫描概率输出\nN拍；valid=1，最后一项done=1')]:p.box(rect,text,size=23)
    p.arrow([(1270,300),(1270,420)]);p.arrow([(1270,540),(1270,690)]);p.arrow([(1270,795),(1270,920)])
    p.arrow([(1530,980),(1605,980),(1605,245),(1530,245)])
    p.text((60,1190),'各扫描/点积状态会在本状态循环，直至当前范围完成。rst_n=0时两个控制器均回空闲。',23)
    p.save('transformer_fsm.png')

if __name__=='__main__':
    hardware();fsm();print(OUT)
