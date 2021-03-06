function [sl_map,salient_im,ft_map]=FrequencyBasedSaliencyDetection(im_in,params)
%DCTbasedSalientDetection 基于频域分析的显著目标检测算法
%对比不同的特征提取方法及滤波器下的显著性检测结果
%使用DCT变换及多种可选的频域变换方法生成显著图：
%   sign函数；
%   log函数
%   sigmod函数；
%   谱残差法
%   均衡化变换
%   SSS
%
%使用3种可选的滤波器生成前景强度图：
%   gauss低通滤波器
%   高斯差分带通滤波器
%   
%
%   输入可以为任意类型任意通道数的图像
%   @im_in      输入的图像
%   @params     显著目标检测参数，包括：选用的频域特征提取方法，生成显著图的滤波方法及参数
%   输出：
%   @sl_map     显著图
%   @salient_im 显著图掩膜下的原图
%   @ft_map     特征强度图

im_in=im2double(im_in);

% 颜色空间选择
if ~isfield( params, 'colorSpace' )
    params.colorSpace=0;
end
im_in_use=colorSpace(im_in,params.colorSpace);

% 计算特征强度图
if ~isfield( params, 'ftPara' )
    params.ftPara.way='sign';
end
ft_map=featureMap(im_in_use,params.ftPara);

% 添加中心化遮罩
if ~isfield( params, 'centra' )
    params.centra=0;
end
ft_map=centralization(ft_map,params.centra);

% 生成显著分布图
if ~isfield( params, 'slPara' )
    params.slPara.kernel='gaussLow';
end
sl_map=salientMap(ft_map,params.slPara);

% 融合原图生成显著区域增强
[n,m,c]=size(im_in);
salient_im=zeros(n,m,c);
for i=1:c
    salient_im(:,:,i)=im_in(:,:,i).*sl_map;
end
end

%% 颜色空间变换函数
function im_out=colorSpace(im_in,colorSpace)
% 对图像进行颜色空间变换，默认为RGB
%   @im_in      输入图像
%   @colorSpace 目标颜色空间
%   @im_out     输出图像

if ~exist( 'colorSpace', 'var' )
    colorSpace='rgb';
end

if strcmp(colorSpace,'lab')
    im_out=double(RGB2Lab(im_in,0))/255;
    im_out(:,:,2:3)=im_out(:,:,2:3)*4-2;  %对uin8型数据的归一化校正
elseif strcmp(colorSpace,'xyz')
    cform=makecform('srgb2xyz');
    im_out=applycform(im_in,cform);
    im_out=im_out/100;  %范围归一化
elseif strcmp(colorSpace,'hsv')
    im_out=rgb2hsv(im_in);
else
    im_out=im_in;
end
    
end

%% 图像中心化
function im_out=centralization(im_in,centra)
% 使用cos遮罩凸显图像中心区域
%   @im_in      输入图像
%   @centra     中心遮罩方式
%   @im_out     添加遮罩的图像

if centra==0
    im_out=im_in;
    return;
end

% 1.计算遮罩
[n,m,c]=size(im_in);
cn=(n+1)/2;
cm=(m+1)/2;
ly=([1:n]-cn)/n;
lx=([1:m]-cm)/m;

if strcmp(centra,'cos')             %cos遮罩
    cosy=cos(ly*pi);
    cosx=cos(lx*pi);
    cover=cosy'*cosx;
elseif strcmp(centra,'binomial')    %二项式遮罩
    ky=1-ly.*ly*2;
    kx=1-lx.*lx*2;
    cover=ky'*kx;
else
    im_out=im_in;
    return;
end

% 执行图像遮罩
im_out=im_in.*cover(:,:,ones(1,c));

end

%% 使用DCT变换及几种可选的频域变换方法生成特征图：
%   sign函数；
%   sigmod函数；
%   log函数
%   谱残差法FR
%   均衡化变换
%   SSS
function ft=featureMap(im_in,ft_param)
%   @im_in      输入的图像
%   @ft_param   选用的频域特征提取方法及参数
%   @ft         特征图

[n,m,c]=size(im_in);
dct_channels=cell(c,1);
ft_channels=cell(c,1);
weight=ones(1,c);
    
way=ft_param.way;

% % 生成背景频谱
% cn=(n+1)/2;
% cm=(m+1)/2;
% ly=([1:n]-cn)/n;
% lx=([1:m]-cm)/m;
% 
% cosy=cos(ly*pi);
% cosx=cos(lx*pi);
% cover=1-cosy'*cosx; %背景遮罩
% 
% backgrd=cell(c,1);
% for i=1:c
%     if strcmp(way,'SSS')
%         backgrd{i}=abs(fft2(im_in(:,:,i).*cover));
%     else
%         backgrd{i}=abs(dct2(im_in(:,:,i).*cover));
%     end
% end

if strcmp(way,'SSS')	%多尺度特征计算
     ft=sssFeatureMap(im_in,1);
     return;
end

% 计算各个通道特征图
for i=1:c
    dct_channels{i}=dct2(im_in(:,:,i));
%     dct_channels{i}=dct_channels{i}.*(1-backgrd{i}./abs(dct_channels{i}));
    
    %信息图
    if strcmp(way,'sign')
        msg_mat=idct2(sign(dct_channels{i}));
    elseif strcmp(way,'sigmod')
        a=sqrt(mean(dct_channels{i}(:).^2));
        msg_mat=idct2(sigmf(dct_channels{i},[1/a,0])*2-1);
    elseif strcmp(way,'frequency equalization')
        if ~isfield( ft_param, 'histNum' )
            ft_param.histNum=4;
        elseif isempty(ft_param.histNum)
            ft_param.histNum=4;
        end
        msg_mat=idct2(frequencyEqualization(dct_channels{i},ft_param.histNum));
    elseif strcmp(way,'log')
        a=sqrt(mean(dct_channels{i}(:).^2));
        msg_mat=idct2(sign(dct_channels{i}).*log(abs(dct_channels{i})/a+1));
    elseif strcmp(way,'SR') %谱残差法
        a=abs(dct_channels{i});
        p=dct_channels{i}./a;
        
        la=log(a+1);
        fr=filter2(ones(5,1)/5,la);
        fr=filter2(ones(1,5)/5,fr);
        fr=la-fr;
        
        msg_mat=idct2(fr.*p);
    elseif strcmp(way,'contrast')	%对比度增强法
        if i==1
            filter_sz=size(dct_channels{i});
            x=[1:filter_sz(2)];
            y=[1:filter_sz(1)];
            kernelF=sigmf(y',[1,1])*sigmf(x,[1,1]);
%             kernelF=ones(filter_sz);
%             kernelF(1,x)=0;kernelF(y,1)=0;
        end
        msg_mat=idct2(dct_channels{i}.*kernelF);
    else
        
    end
    
    ft_channels{i}=msg_mat.*msg_mat; %特征图
    weight(i)=(std(ft_channels{i}(:))/(mean(ft_channels{i}(:))+0.0000001))^4;   %通道权重
end

% 特征图通道融合
% 根据各个色度平均强度与图像平均强度之间的区别，计算权值
if c>1
    ft=ft_channels{1};
    for i=2:c
        ft=ft+ft_channels{i}*weight(i);
    end
    ft=ft/sum(weight);
else
    ft=ft_channels{1};
end
end

function fe_out=frequencyEqualization(fq_im,hist_num)
% 频域均衡化函数
% 将频域强度均衡化映射到[-1,1]之间
%   @fq_im      输入的图像
%   @hist_num   直方图数量
%   @fe_out     均衡化后的图像

if ~exist( 'hist_num', 'var' )
    hist_num=4;
elseif isempty(hist_num)
    hist_num=4;
end

% 正负分别统计直方图
max_p=max(fq_im(:));
min_p=min(fq_im(:));

st_hn=hist_num*2;       %统计直方图个数
hist_p=zeros(st_hn,1);    %正幅度直方图
hist_n=zeros(st_hn,1);    %负幅度直方图

map_p=ceil(fq_im/(max_p/st_hn));
map_n=ceil(fq_im/(min_p/st_hn));

for i=1:st_hn
    eq_mat=(map_p==i);
    hist_p(i)=sum(eq_mat(:));
    
    eq_mat=(map_n==i);
    hist_n(i)=sum(eq_mat(:));
end
hist_p=hist_p/sum(hist_p);  %归一化
hist_n=hist_n/sum(hist_n);

% 计算映射
fix_p=zeros(st_hn,1);
fix_n=zeros(st_hn,1);

cur_pst=0;
cur_ngt=0;
for i=1:st_hn
    cur_pst=cur_pst+hist_p(i);
    cur_ngt=cur_ngt+hist_n(i);
    
    fix_p(i)=ceil(cur_pst*hist_num);
    fix_n(i)=-ceil(cur_ngt*hist_num);
end

fix_p=fix_p/hist_num;
fix_n=fix_n/hist_num;

% 均衡化
fe_out=zeros(size(fq_im));
for i=1:st_hn
    eq_mat=(map_p==i);
    fe_out(eq_mat)=fix_p(i);
    
    eq_mat=(map_n==i);
    fe_out(eq_mat)=fix_n(i);
end
end

function ft=sssFeatureMap(im_in,max_pix)
%采用SSS方法生成一单通道特征图
[n,m,c]=size(im_in);

%1.计算FFT频谱强度及相位
fft_map=zeros(n,m,c);
for i=1:c
    fft_map(:,:,i)=fft2(im_in(:,:,i));
end
a_map=abs(fft_map);     %幅度
fft_map=fft_map./(a_map+0.00001*(a_map==0)); %相位

for i=1:c
    a_map(:,:,i)=fftshift(a_map(:,:,i));  %将低频放到图像中心
end
a_map=log(a_map+1);

% 计算卷积核
x_sz=[1:31]-16;
gkx=exp(-(-4:4).^2/8);
gky=gkx';

% 多次卷积
ft=zeros(size(im_in));
max_w=0;

for sz=0:7
    kernel_x=exp(-x_sz.^2/(0.25*2^sz));
    kernel_x=kernel_x./sum(kernel_x);

    % 幅度谱卷积
    cur_ft=imfilter(a_map,kernel_x);
    cur_ft=imfilter(cur_ft,kernel_x');
    for i=1:c
        cur_ft(:,:,i)=fftshift(cur_ft(:,:,i));
    end
    cur_ft=exp(cur_ft)-1;
    
    % 特征图
    cur_ft_sm=ifft2(cur_ft(:,:,1).*fft_map(:,:,1));
    cur_ft_sm=cur_ft_sm.*conj(cur_ft_sm);
    for i=2:c
        cur_ft_c=ifft2(cur_ft(:,:,i).*fft_map(:,:,i));
        cur_ft_sm=cur_ft_sm+cur_ft_c.*conj(cur_ft_c);
    end
    cur_ft_sm=cur_ft_sm.*(max_pix/max(cur_ft_sm(:)));  %归一化幅度
    
    % 高斯滤波
    cur_ft_sm=imfilter(cur_ft_sm,gkx);
    cur_ft_sm=imfilter(cur_ft_sm,gky);
    
    % 计算特征图熵
%     hmp=ceil(cur_ft*4); %分层统计结果
%     hp=zeros(4,1);      %统计个数
%     for j=1:4
%         hp(j)=sum(sum(hmp==j));
%     end
%     hp=hp/pix_n;
%     hs=-hp'*(log(hp+0.01));%熵
%     
%     if hs<min_hs
%         ft=cur_ft;
%         min_hs=hs;
%     end

    weight=(std(cur_ft_sm(:))/mean(cur_ft_sm(:))+0.0001)^6;
    
    if weight>max_w
        ft=cur_ft_sm;
        max_w=weight;
    end
end
end
%% 使用几种可选的滤波器生成显著图：
%   gauss低通滤波器
%   高斯差分带通滤波器
%   
function sl_map=salientMap(ft_map,sl_param)
%   @ft_map     特征图
%   @sl_param   选用的滤波器方法及参数
%   @sl_map     显著图

if ~isfield( sl_param, 'kernel' )
    sl_param.kernel='gaussLow';
elseif isempty(sl_param.kernel)
    sl_param.kernel='gaussLow';
end

if ~isfield( sl_param, 'size' )
    sl_param.size=[0.1,0.5];
elseif isempty(sl_param.size)
    sl_param.size=[0.1,0.5];
end

% 计算特征图DCT
ft_F=dct2(ft_map);

% 生成滤波器
[n,m]=size(ft_F);
kernel=sl_param.kernel;
if strcmp(kernel,'gaussLow')
    fq=1./min(sl_param.size);	%目标尺寸对应截止频率
    kernelF=gaussFilterFq([n,m],[0,0],[fq,fq]);
elseif strcmp(kernel,'gaussBand')
    fq=(1./sl_param.size(1)+1./sl_param.size(2))/2;	%目标尺寸对应截止频率
    df=abs(1./sl_param.size(1)-1./sl_param.size(2));
    kernelF=gaussFilterFq([n,m],[fq,fq],[df,df]);
elseif strcmp(kernel,'DOG')
    fq=1./sl_param.size;        %频率范围
    ef=max(fq);  %截止频率
    sf=min(fq);                 %起始频率
    kernelF=gaussFilterFq([n,m],[0,0],[ef,ef])-gaussFilterFq([n,m],[0,0],[sf,sf]);
elseif strcmp(kernel,'biasBand')
    %根据频率范围计算参数
    fq=1./sl_param.size;    %频率范围
    fq_min=min(fq);fq_max=max(fq);
    b=log(0.1)/(2*fq_min*log(fq_max/2/fq_min)-fq_max+2*fq_min); %顶点值的0.1
    a=2*b*fq_min;   %顶点前一半
    
    kernelF=biasBandFq([n,m],a,b);
else
    
end

% 获得显著图
sl_map=idct2(ft_F.*kernelF);

% 归一化
sl_map=sl_map./max(sl_map(:));
end

function kernelF=gaussFilterFq(filter_sz,u0,delta)
% 生成DCT变换的2维频域高斯滤波器
%   @filter_sz  滤波器尺寸，格式为[height,width]
%   @u0         均值，格式为[u0_y,u0_x]
%   @delta      标准差，格式为[delta_y,delta_x]

dx=[1:filter_sz(2)]-u0(2);
dy=[1:filter_sz(1)]-u0(1);
delta=2*delta.^2;

kx=exp(-dx.*dx/delta(2));
ky=exp(-dy.*dy/delta(1));
kernelF=ky'*kx;
end

function kernelF=biasBandFq(filter_sz,a,b)
% 生成DCT变换的2维频域x^a*exp(-b*x)滤波器
%   @filter_sz  滤波器尺寸，格式为[height,width]
%   @a          次幂参数
%   @b      	指数参数

x=[0:filter_sz(2)-1];
y=[0:filter_sz(1)-1];

max_num=(a/b)^a*exp(-a);
kx=x.^a.*exp(-b*x)/max_num;
ky=y.^a.*exp(-b*y)/max_num;
kernelF=ky'*kx;
end 