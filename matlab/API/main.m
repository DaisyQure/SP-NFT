% 20200604
% HOUSE
% Demo : online receive data stream 
clear;
clc;
% 初始化DataServer对象
deviceMontage = {'POz','PO3','PO4','PO5','PO6','Oz','O1','O2','TRG'};
device = 'Neuracle';     % see DataParser for supported devices
ipAddress = '127.0.0.1'; % IP address of the DataSerive in EEG Recorder
serverPort = 8712;       % port of the DataSerive in EEG Recorder
nChan = length(deviceMontage);
sampleRate = 1000;       % Hz
timeRingbuffer = 4;      % Second
dataServer = DataServer(device, nChan, ipAddress, serverPort, sampleRate, timeRingbuffer); 
% 打开DataServer,开始接收上游数据并解析
dataServer.Open();
% 每隔0.2s画出第一导数据（数据长度=timeRingbuffer）
figure
while i<100
    data = dataServer.GetBufferData(); % get数据
    plot(data(1,:));
    pause(0.2)
    i=i+1;
end
% 关闭DataServer,停止接收数据
dataServer.Close();