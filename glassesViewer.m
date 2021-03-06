function hm = glassesViewer
close all

qDEBUG = false;
if qDEBUG
    dbstop if error
end

addpath(genpath('function_library'))

% select the folder of a recording to display. This needs to point to a
% specific recording's folder. if "projects" is the project folder on the
% SD card, an example of a specific recording is:
%   projects\rkamrkb\recordings\zi4xmt2
if 1
    filedir = uigetdir('','Select recording folder');
else
    % for easy use, hardcode a folder. 
    filedir = '';
end
if ~filedir
    return
end



%% init figure
hm=figure('Visible','off');
hm.Name='Tobii Glasses 2 Viewer';
hm.NumberTitle = 'off';
hm.Units = 'pixels';
hm.CloseRequestFcn = @KillCallback;
hm.WindowKeyPressFcn = @KeyPress;
hm.WindowButtonMotionFcn = @MouseMove;
hm.WindowButtonDownFcn = @MouseClick;
hm.WindowButtonUpFcn = @MouseRelease;
hm.MenuBar = 'none';

% set figure to near full screen
ws          = get(0,'ScreenSize');
hmmar       = [0 0 0 40];    % left right top bottom
hm.OuterPosition = [ws(1) + hmmar(1), ws(2) + hmmar(4), ws(3)-hmmar(1)-hmmar(2), ws(4)-hmmar(3)-hmmar(4)];

% need to figure out if any DPI scaling active, some components work in
% original screen space
hm.UserData.ui.DPIScale             = getDPIScale();

%% global options and starting values
hm.UserData.settings.plot.removeAccDC        = true; % remove DC from the accelerometer trace?
hm.UserData.settings.plot.SGWindowVelocity   = 20;   % ms (gets adjusted below if not matching sampling frequency of data)

hm.UserData.plot.timeWindow             = 2;    % s
plotOrder                               = {'azi','gyro','ele','vel','pup','acc'};   % do not make a settings, as it'll be stored by means of tags in the axes themselves. this one could only get stale...
hm.UserData.settings.plot.aziLim        = 45;
hm.UserData.settings.plot.eleLim        = 30;
hm.UserData.settings.plot.velLim        = 400;
hm.UserData.settings.plot.gyroLim       = 150;
hm.UserData.settings.plot.lineWidth     = 1;    % pix

%% setup time
% setup main time and timer for smooth playback
hm.UserData.time.tickPeriod     = 0.05; % 20Hz hardcoded (doesn't have to update so frequently, that can't be displayed by this GUI anyway)
hm.UserData.time.timeIncrement  = hm.UserData.time.tickPeriod;   % change to play back at slower rate
hm.UserData.time.stepMultiplier = 0.01; % timestep per 1 unit of button press (we have buttons for moving by 1 and by 10 units)
hm.UserData.time.currentTime    = 0;
hm.UserData.time.endTime        = nan;   % determined below when videos are loaded
hm.UserData.time.mainTimer      = timer('Period', hm.UserData.time.tickPeriod, 'ExecutionMode', 'fixedRate', 'TimerFcn', @(~,evt) timerTick(evt,hm), 'BusyMode', 'drop', 'TasksToExecute', inf, 'StartFcn',@(~,evt) initPlayback(evt,hm));

%% load data
% read glasses data
hm.UserData.data = getTobiiDataFromGlasses(filedir,qDEBUG);
hm.UserData.ui.haveEyeVideo = isfield(hm.UserData.data.videoSync,'eye');
% update figure title
hm.Name = [hm.Name ' (' hm.UserData.data.name ')'];


%% setup data axes
% make test axis to see how much margins are
temp    = axes('Units','pixels','OuterPosition',[0 floor(hm.Position(4)/2) floor(hm.Position(3)/2) floor(hm.Position(4)/6)],'YLim',[-200 200]);
drawnow
opos    = temp.OuterPosition;
pos     = temp.Position;
temp.YLabel.String = 'azi (�)';
drawnow
opos2   = temp.OuterPosition;
posy    = temp.Position;
temp.XLabel.String = 'time (s)';
drawnow
opos3   = temp.OuterPosition;
posxy   = temp.Position;
delete(temp);
assert(isequal(opos,opos2,opos3))

% determine margins
hm.UserData.plot.margin.base    = pos  -opos;
hm.UserData.plot.margin.y       = posy -opos-hm.UserData.plot.margin.base;
hm.UserData.plot.margin.xy      = posxy-opos-hm.UserData.plot.margin.base-hm.UserData.plot.margin.y;
hm.UserData.plot.margin.between = 8;

% setup plot axes
setupPlots(hm,plotOrder);

% make axes and plot data
nPanel = length(plotOrder);
hm.UserData.plot.ax = gobjects(1,nPanel);
hm.UserData.plot.defaultValueScale = zeros(2,nPanel);
commonPropAxes = {'XGrid','on','GridLineStyle','-','NextPlot','add','Parent',hm,'XTickLabel',{},'Units','pixels','XLim',[0 hm.UserData.plot.timeWindow],'Layer','top'};
commonPropPlot = {'HitTest','off','LineWidth',hm.UserData.settings.plot.lineWidth};
% we have:
for a=1:nPanel
    switch plotOrder{a}
        case 'azi'
            % 1. azimuth
            hm.UserData.plot.defaultValueScale(:,a) = [hm.UserData.settings.plot.aziLim.*[-1 1]];
            hm.UserData.plot.ax(a) = axes(commonPropAxes{:},'Position',hm.UserData.plot.axPos(a,:),'YLim',hm.UserData.plot.defaultValueScale(:,a),'Tag','azi');
            hm.UserData.plot.ax(a).YLabel.String = 'azi (�)';
            plot(hm.UserData.data.eye. left.ts,hm.UserData.data.eye. left.azi,'r','Parent',hm.UserData.plot.ax(a),'Tag','data|left',commonPropPlot{:});
            plot(hm.UserData.data.eye.right.ts,hm.UserData.data.eye.right.azi,'b','Parent',hm.UserData.plot.ax(a),'Tag','data|right',commonPropPlot{:});
        case 'ele'
            % 2. elevation
            hm.UserData.plot.defaultValueScale(:,a) = [hm.UserData.settings.plot.eleLim.*[-1 1]];
            hm.UserData.plot.ax(a) = axes(commonPropAxes{:},'Position',hm.UserData.plot.axPos(a,:),'YLim',hm.UserData.plot.defaultValueScale(:,a),'Tag','ele');
            hm.UserData.plot.ax(a).YLabel.String = 'ele (�)';
            hm.UserData.plot.ax(a).YDir = 'reverse';
            plot(hm.UserData.data.eye. left.ts,hm.UserData.data.eye. left.ele,'r','Parent',hm.UserData.plot.ax(a),'Tag','data|left',commonPropPlot{:});
            plot(hm.UserData.data.eye.right.ts,hm.UserData.data.eye.right.ele,'b','Parent',hm.UserData.plot.ax(a),'Tag','data|right',commonPropPlot{:});
        case 'vel'
            % 3. velocity
            hm.UserData.settings.plot.SGWindowVelocity = max(2,round(hm.UserData.settings.plot.SGWindowVelocity/1000*hm.UserData.data.eye.fs))*1000/hm.UserData.data.eye.fs;    % min SG window is 2*sample duration
            velL = getVelocity(hm,hm.UserData.data.eye. left,hm.UserData.settings.plot.SGWindowVelocity,hm.UserData.data.eye.fs);
            velR = getVelocity(hm,hm.UserData.data.eye.right,hm.UserData.settings.plot.SGWindowVelocity,hm.UserData.data.eye.fs);
            hm.UserData.plot.defaultValueScale(:,a) = [0 min(nanmax([velL(:); velR(:)]),hm.UserData.settings.plot.velLim)];
            hm.UserData.plot.ax(a) = axes(commonPropAxes{:},'Position',hm.UserData.plot.axPos(a,:),'YLim',hm.UserData.plot.defaultValueScale(:,a),'Tag','vel');
            hm.UserData.plot.ax(a).YLabel.String = 'vel (�/s)';
            plot(hm.UserData.data.eye. left.ts,velL,'r','Parent',hm.UserData.plot.ax(a),'Tag','data|left',commonPropPlot{:});
            plot(hm.UserData.data.eye.right.ts,velR,'b','Parent',hm.UserData.plot.ax(a),'Tag','data|right',commonPropPlot{:});
        case 'pup'
            % 4. pupil
            hm.UserData.plot.defaultValueScale(:,a) = [0 nanmax([hm.UserData.data.eye.left.pd(:); hm.UserData.data.eye.right.pd(:)])];
            hm.UserData.plot.ax(a) = axes(commonPropAxes{:},'Position',hm.UserData.plot.axPos(a,:),'YLim',hm.UserData.plot.defaultValueScale(:,a),'Tag','pup');
            hm.UserData.plot.ax(a).YLabel.String = 'pup (mm)';
            plot(hm.UserData.data.eye. left.ts,hm.UserData.data.eye. left.pd,'r','Parent',hm.UserData.plot.ax(a),'Tag','data|left',commonPropPlot{:});
            plot(hm.UserData.data.eye.right.ts,hm.UserData.data.eye.right.pd,'b','Parent',hm.UserData.plot.ax(a),'Tag','data|right',commonPropPlot{:});
        case 'gyro'
            % 5. gyroscope
            hm.UserData.plot.defaultValueScale(:,a) = [max(nanmin(hm.UserData.data.gyroscope.gy(:)),-hm.UserData.settings.plot.gyroLim) min(nanmax(hm.UserData.data.gyroscope.gy(:)),hm.UserData.settings.plot.gyroLim)];
            hm.UserData.plot.ax(a) = axes(commonPropAxes{:},'Position',hm.UserData.plot.axPos(a,:),'YLim',hm.UserData.plot.defaultValueScale(:,a),'Tag','gyro');
            hm.UserData.plot.ax(a).YLabel.String = 'gyro (�/s)';
            plot(hm.UserData.data.gyroscope.ts,hm.UserData.data.gyroscope.gy(:,1),'r','Parent',hm.UserData.plot.ax(a),'Tag','data|x',commonPropPlot{:});
            plot(hm.UserData.data.gyroscope.ts,hm.UserData.data.gyroscope.gy(:,2),'b','Parent',hm.UserData.plot.ax(a),'Tag','data|y',commonPropPlot{:});
            plot(hm.UserData.data.gyroscope.ts,hm.UserData.data.gyroscope.gy(:,3),'g','Parent',hm.UserData.plot.ax(a),'Tag','data|z',commonPropPlot{:});
        case 'acc'
            % 6. accelerometer
            ac = hm.UserData.data.accelerometer.ac;
            if hm.UserData.settings.plot.removeAccDC
                ac = ac-nanmean(ac,1);
            end
            hm.UserData.plot.defaultValueScale(:,a) = [nanmin(ac(:)) nanmax(ac(:))];
            hm.UserData.plot.ax(a) = axes(commonPropAxes{:},'Position',hm.UserData.plot.axPos(a,:),'YLim',hm.UserData.plot.defaultValueScale(:,a),'Tag','acc');
            hm.UserData.plot.ax(a).YLabel.String = 'acc (m/s^2)';
            plot(hm.UserData.data.accelerometer.ts,ac(:,1),'r','Parent',hm.UserData.plot.ax(a),'Tag','data|x',commonPropPlot{:});
            plot(hm.UserData.data.accelerometer.ts,ac(:,2),'b','Parent',hm.UserData.plot.ax(a),'Tag','data|y',commonPropPlot{:});
            plot(hm.UserData.data.accelerometer.ts,ac(:,3),'g','Parent',hm.UserData.plot.ax(a),'Tag','data|z',commonPropPlot{:});
        otherwise
            error('data panel type ''%s'' not understood',plotOrder{a});
    end
end
% setup x axis of bottom plot
hm.UserData.plot.ax(end).XLabel.String = 'time (s)';
hm.UserData.plot.ax(end).XTickLabelMode = 'auto';

% setup time indicator line on each plot
hm.UserData.plot.timeIndicator = gobjects(size(hm.UserData.plot.ax));
for p=1:length(hm.UserData.plot.ax)
    hm.UserData.plot.timeIndicator(p) = plot([nan nan], hm.UserData.plot.ax(p).YLim,'r-','Parent',hm.UserData.plot.ax(p),'Tag',['timeIndicator|' hm.UserData.plot.ax(p).Tag]);
end

% plot UI for dragging time and scrolling the whole window
hm.UserData.ui.hoveringTime         = false;
hm.UserData.ui.grabbedTime          = false;
hm.UserData.ui.grabbedTimeLoc       = nan;
hm.UserData.ui.justMovedTimeByMouse = false;
hm.UserData.ui.scrollRef            = [nan nan];
hm.UserData.ui.scrollRefAx          = matlab.graphics.GraphicsPlaceholder;

% reset plot limits button
butPos = [hm.UserData.plot.axRect(end,3)+10 hm.UserData.plot.axRect(end,2) 100 30];
hm.UserData.ui.resetPlotLimitsButton = uicomponent('Style','pushbutton', 'Parent', hm,'Units','pixels','Position',butPos, 'String','Reset plot Y-limits','Tag','resetValueLimsButton','Callback',@(~,~,~) resetPlotValueLimits(hm));

% legend (faked with just an axis)
axHeight = 110;
axPos = [butPos(1) sum(butPos([2 4]))+10 butPos(3)*.7 axHeight];
hm.UserData.ui.signalLegend = axes('NextPlot','add','Parent',hm,'XTick',[],'YTick',[],'Units','pixels','Position',axPos,'Box','on','XLim',[0 .7],'YLim',[0 1],'YDir','reverse');
tcommon = {'VerticalAlignment','middle','Parent',hm.UserData.ui.signalLegend};
lcommon = {'Parent',hm.UserData.ui.signalLegend,'LineWidth',2};
% text+line+line+text+line+line+line = 7 elements
height     = diff(hm.UserData.ui.signalLegend.YLim);
heightEach = height/7;
width      = diff(hm.UserData.ui.signalLegend.XLim);
% 1st header
text(.05,heightEach*.5,'eye data','FontWeight','bold',tcommon{:});
% left eye
plot([.05 0.20],heightEach*1.5.*[1 1],'r',lcommon{:})
text(.25,heightEach*1.5,'left',tcommon{:});
% right eye
plot([.05 0.20],heightEach*2.5.*[1 1],'b',lcommon{:})
text(.25,heightEach*2.5,'right','VerticalAlignment','middle','Parent',hm.UserData.ui.signalLegend);
% 2nd header
text(.05,hm.UserData.ui.signalLegend.YLim(2)-heightEach*3.5,'IMU data','FontWeight','bold',tcommon{:});
% X
plot([.05 0.20],heightEach*4.5.*[1 1],'r',lcommon{:})
text(.25,heightEach*4.5,'X',tcommon{:});
% Y
plot([.05 0.20],heightEach*5.5.*[1 1],'b',lcommon{:})
text(.25,heightEach*5.5,'Y',tcommon{:});
% Z
plot([.05 0.20],heightEach*6.5.*[1 1],'g',lcommon{:})
text(.25,heightEach*6.5,'Z',tcommon{:});



%% load videos
segments = FolderFromFolder(fullfile(filedir,'segments'));
for s=1:length(segments)
    for p=1:1+hm.UserData.ui.haveEyeVideo
        switch p
            case 1
                file = 'fullstream.mp4';
            case 2
                file = 'eyesstream.mp4';
        end
        hm.UserData.vid.objs(s,p) = makeVideoReader(fullfile(filedir,'segments',segments(s).name,file),false);
        % for warmup, read first frame
        hm.UserData.vid.objs(s,p).StreamHandle.read(1);
    end
end


%% setup video on figure
% determine axis locations
if hm.UserData.ui.haveEyeVideo
    % 1. right half for video. 70% of its width for scene, 30% for eye
    sceneVidWidth = .7;
    eyeVidWidth   = .3;
    assert(sceneVidWidth+eyeVidWidth==1)
    sceneVidAxSz  = hm.Position(3)/2*sceneVidWidth.*[1 1./hm.UserData.vid.objs(1,1).AspectRatio];
    eyeVidAxSz    = hm.Position(3)/2*  eyeVidWidth.*[1 1./hm.UserData.vid.objs(1,2).AspectRatio];
    if eyeVidAxSz(2)>hm.Position(4)
        % scale down to fit
        eyeVidAxSz= eyeVidAxSz.*(hm.Position(4)/eyeVidAxSz(2));
    end
    if eyeVidAxSz(1)+sceneVidAxSz(1)<hm.Position(3)/2
        % enlarge scene video, we have some space left
        leftOver = hm.Position(3)/2-eyeVidAxSz(1)-sceneVidAxSz(1);
        sceneVidAxSz = (sceneVidAxSz(1)+leftOver).*[1 1./hm.UserData.vid.objs(1,1).AspectRatio];
    end
    
    axpos(1,:)  = [hm.Position(3)/2+1 hm.Position(4)-round(sceneVidAxSz(2)) round(sceneVidAxSz(1)) round(sceneVidAxSz(2))];
    axpos(2,:)  = [axpos(1,1)+axpos(1,3)+1 hm.Position(4)-round(eyeVidAxSz(2)) round(eyeVidAxSz(1)) round(eyeVidAxSz(2))];
else
    % 40% of interface is for scene video
    sceneVidAxSz  = hm.Position(3)*.4.*[1 1./hm.UserData.vid.objs(1,1).AspectRatio];
    axpos(1,:)  = [hm.Position(3)*.6+1 hm.Position(4)-round(sceneVidAxSz(2)) round(sceneVidAxSz(1)) round(sceneVidAxSz(2))];
end

% create axes
for p=1:1+hm.UserData.ui.haveEyeVideo
    hm.UserData.vid.ax(p) = axes('units','pixels','position',axpos(p,:),'visible','off');
    
    % Setup the default axes for video display.
    set(hm.UserData.vid.ax(p), ...
        'Visible','off', ...
        'XLim',[0.5 hm.UserData.vid.objs(1,p).Dimensions(2)+.5], ...
        'YLim',[0.5 hm.UserData.vid.objs(1,p).Dimensions(1)+.5], ...
        'YDir','reverse', ...
        'XLimMode','manual',...
        'YLimMode','manual',...
        'ZLimMode','manual',...
        'CLimMode','manual',...
        'ALimMode','manual',...
        'Layer','bottom',...
        'HitTest','off',...
        'NextPlot','add', ...
        'DataAspectRatio',[1 1 1]);
    if p==2
        % for eye video, need to reverse axis
        hm.UserData.vid.ax(p).XDir = 'reverse';
    end
    
    % image plot type
    hm.UserData.vid.im(p) = image(...
        'XData', [1 hm.UserData.vid.objs(1,p).Dimensions(2)], ...
        'YData', [1 hm.UserData.vid.objs(1,p).Dimensions(1)], ...
        'Tag', 'VideoImage',...
        'Parent',hm.UserData.vid.ax(p),...
        'HitTest','off',...
        'CData',zeros(hm.UserData.vid.objs(1,p).Dimensions,'uint8'));
end
% create data trail on video
hm.UserData.vid.gt = plot(nan,nan,'r-','Parent',hm.UserData.vid.ax(1),'Visible','off','HitTest','off');
% create gaze marker (NB: size is marker area, not diameter or radius)
hm.UserData.vid.gm = scatter(0,0,'Marker','o','SizeData',10^2,'MarkerFaceColor',[1 0 0],'MarkerFaceAlpha',0.6,'MarkerEdgeColor','none','Parent',hm.UserData.vid.ax(1),'HitTest','off');

% We expect to have one video at roughly 50Hz and one at roughly 25.
% hardcode, but check
assert(round(1./hm.UserData.vid.objs(1,1).FrameRate,2)==0.04 && (~hm.UserData.ui.haveEyeVideo || round(1./hm.UserData.vid.objs(1,2).FrameRate,2)==0.02))
% if multiple segments, find switch point
hm.UserData.vid.switchFrames(:,1) = [0 cumsum(hm.UserData.data.videoSync.scene.segframes)];
if hm.UserData.ui.haveEyeVideo
    hm.UserData.time.endTime = min([hm.UserData.data.videoSync.scene.fts(end) hm.UserData.data.videoSync.eye.fts(end)]);
    hm.UserData.vid.switchFrames(:,2) = [0 cumsum(hm.UserData.data.videoSync.eye.segframes)];
else
    hm.UserData.time.endTime = hm.UserData.data.videoSync.scene.fts(end);
end
hm.UserData.vid.currentFrame = [0 0];



%% setup play controls
hm.UserData.ui.VCR.state.playing = false;
hm.UserData.ui.VCR.state.cyclePlay = false;
vidPos = hm.UserData.vid.ax(1).Position;
% slider for rapid time navigation
sliderSz = [vidPos(3) 40];
sliderPos= [vidPos(1) vidPos(2)-sliderSz(2) sliderSz];
hm.UserData.ui.VCR.slider.fac= 100;
hm.UserData.ui.VCR.slider.raw = com.jidesoft.swing.RangeSlider(0,hm.UserData.time.endTime*hm.UserData.ui.VCR.slider.fac,0,hm.UserData.plot.timeWindow*hm.UserData.ui.VCR.slider.fac);
hm.UserData.ui.VCR.slider.jComp = uicomponent(hm.UserData.ui.VCR.slider.raw,'Parent',hm,'Units','pixels','Position',sliderPos);
hm.UserData.ui.VCR.slider.jComp.StateChangedCallback = @(hndl,evt) sliderChange(hm,hndl,evt);
hm.UserData.ui.VCR.slider.jComp.MousePressedCallback = @(hndl,evt) sliderClick(hm,hndl,evt);
hm.UserData.ui.VCR.slider.jComp.KeyPressedCallback = @(hndl,evt) KeyPress(hm,hndl,evt);
hm.UserData.ui.VCR.slider.jComp.SnapToTicks = false;
hm.UserData.ui.VCR.slider.jComp.PaintTicks = true;
hm.UserData.ui.VCR.slider.jComp.PaintLabels = true;
hm.UserData.ui.VCR.slider.jComp.RangeDraggable = false; % doesn't work together with overridden click handling logic. don't want to try and detect dragging and then cancel click logic, too complicated
% draw extra line indicating timepoint
% Need end points of actual range in slider, get later when GUI is fully
% instantiated
hm.UserData.ui.VCR.slider.left  = nan;
hm.UserData.ui.VCR.slider.right = nan;
hm.UserData.ui.VCR.slider.offset= sliderPos(1:2);
lineSz = round([2 sliderSz(2)/2]*hm.UserData.ui.DPIScale);
hm.UserData.ui.VCR.line.raw = javax.swing.JLabel(javax.swing.ImageIcon(im2java(cat(3,ones(lineSz([2 1])),zeros(lineSz([2 1])),zeros(lineSz([2 1]))))));
hm.UserData.ui.VCR.line.jComp = uicomponent(hm.UserData.ui.VCR.line.raw,'Parent',hm,'Units','pixels','Position',[vidPos(1) vidPos(2)-lineSz(2)*2/hm.UserData.ui.DPIScale lineSz./hm.UserData.ui.DPIScale]);

% figure out tick spacing and make custom labels
labelTable = java.util.Hashtable();
% divide into no more than 12 intervals
if ceil(hm.UserData.time.endTime/11)>60
    % minutes
    stepLbls = 0:ceil(hm.UserData.time.endTime/60/11):hm.UserData.time.endTime/60;
    steps    = stepLbls*60;
else
    % seconds
    stepLbls = 0:ceil(hm.UserData.time.endTime/11):hm.UserData.time.endTime;
    steps    = stepLbls;
end
for p=1:length(stepLbls)
    labelTable.put( int32( steps(p)*hm.UserData.ui.VCR.slider.fac ), javax.swing.JLabel(sprintf('%d',stepLbls(p))) );
end
hm.UserData.ui.VCR.slider.jComp.LabelTable=labelTable;
hm.UserData.ui.VCR.slider.jComp.MajorTickSpacing = steps(2)*hm.UserData.ui.VCR.slider.fac;
hm.UserData.ui.VCR.slider.jComp.MinorTickSpacing = steps(2)/5*hm.UserData.ui.VCR.slider.fac;

% usual VCR buttons, and a few special ones
butSz = [30 30];
gfx = load('icons');
buttons = {
    'pushbutton','PrevWindow','|jump_to','Previous window',@(~,~,~) jumpWin(hm,-1),{}
    'pushbutton','NextWindow','jump_to','Next window',@(~,~,~) jumpWin(hm, 1),{}
    'space','','','','',''
    'pushbutton','GotoStart','goto_start_default','Go to start',@(~,~,~) seek(hm,-inf),{}
    'pushbutton','Rewind','rewind_default','Jump back (1 s)',@(~,~,~) seek(hm,-1),{}
    'pushbutton','StepBack','step_back','Step back (1 sample)',@(~,~,~) seek(hm,-1/hm.UserData.data.eye.fs),{}
    %'Stop',{'stop_default'}
    'pushbutton','Play',{'play_on', 'pause_default'},{'Play','Pause'},@(src,~,~) startStopPlay(hm,-1,src),{}
    'pushbutton','StepFwd','step_fwd', 'Step forward (1 sample)',@(~,~,~) seek(hm,1/hm.UserData.data.eye.fs),{}
    'pushbutton','FFwd','ffwd_default', 'Jump forward (1 s)',@(~,~,~) seek(hm,1),{}
    'pushbutton','GotoEnd','goto_end_default', 'Go to end',@(~,~,~) seek(hm,inf),{}
    'space','','','','',''
    'togglebutton','Cycle','repeat_on', {'Cycle in time window','Play normally'},@(src,~,~) toggleCycle(hm,src),{}
    'togglebutton','Trail','revertToScope', {'Switch on data trail','Switch off data trail'},@(src,~,~) toggleDataTrail(hm,src),{}
    };
totSz   = [size(buttons,1)*butSz(1) butSz(2)];
left    = vidPos(1)+vidPos(3)/2-totSz(1)/2;
bottom  = vidPos(2)-2-butSz(2)-sliderSz(2);
% get gfx
for p=1:size(buttons,1)
    if strcmp(buttons{p,1},'space')
        continue;
    end
    if iscell(buttons{p,3})
        buttons{p,3} = cellfun(@(x) getIcon(gfx,x),buttons{p,3},'uni',false);
    else
        buttons{p,3} = getIcon(gfx,buttons{p,3});
    end
end
% create buttons
hm.UserData.ui.VCR.but = gobjects(1,size(buttons,1));
for p=1:size(buttons,1)
    if strcmp(buttons{p,1},'space')
        continue;
    end
    icon = buttons{p,3};
    toolt= buttons{p,4};
    UsrDat = [];
    if iscell(buttons{p,3})
        icon = buttons{p,3}{1};
        UsrDat= [UsrDat buttons(p,3)];
    end
    if iscell(buttons{p,4})
        toolt= buttons{p,4}{1};
        UsrDat= [UsrDat buttons(p,4)];
    end
    hm.UserData.ui.VCR.but(p) = uicontrol(...
    'Style',buttons{p,1},...
    'Tag',buttons{p,2},...
    'Position',[left+(p-1)*butSz(1) bottom butSz],...
    'TooltipString',toolt,...
    'CData',icon,...
    'Callback',buttons{p,5},...
    buttons{p,6}{:},...
    'UserData',UsrDat...
    );
end

% make settings panel
createSettings(hm);

%% all done, make sure GUI is shown
hm.Visible = 'on';
drawnow;
% do some inits only possible when figure is visible
doPostInit(hm);
updateTime(hm);
drawnow;

if nargout==0
    % assign hm in base, so we can just run this function with F5 and still
    % observe state of the GUI from the command line
    assignin('base','hm',hm);
end
end




%% helpers etc
function setupPlots(hm,plotOrder,nTotal)
nPanel  = length(plotOrder);
if nargin<3
    nTotal = nPanel;
end
if hm.UserData.ui.haveEyeVideo
    widthFac = .5;
else
    widthFac = .6;
end

width   = widthFac*hm.Position(3)-hm.UserData.plot.margin.base(1)-hm.UserData.plot.margin.y(1);   % half of window width, but leave space left of axis for tick labels and axis label
height  = (hm.Position(4) -(nPanel-1)*hm.UserData.plot.margin.between -hm.UserData.plot.margin.base(2)-hm.UserData.plot.margin.xy(2))/nPanel; % vertical height of window, minus nPanel-1 times space between panels, minus space below axis for tick labels and axis label
left    = hm.UserData.plot.margin.base(1)+hm.UserData.plot.margin.y(1);                     % leave space left of axis for tick labels and axis label
heights = repmat(height,nPanel,1);
bottom  = repmat(hm.Position(4),nPanel,1)-cumsum(heights)-cumsum([0; repmat(hm.UserData.plot.margin.between,nPanel-1,1)]);

hm.UserData.plot.axPos = [repmat(left,nPanel,1) bottom repmat(width,nPanel,1) heights];
if nPanel<nTotal
    % add place holders, need to preserve shape
    hm.UserData.plot.axPos = [hm.UserData.plot.axPos; nan(nTotal-nPanel,4)];
end

hm.UserData.plot.axRect= [hm.UserData.plot.axPos(:,1:2) hm.UserData.plot.axPos(:,1:2)+hm.UserData.plot.axPos(:,3:4)];
end

function vel = getVelocity(hm,data,velWindow,fs)
% span of filter, use minimum length of saccade. Its very important to not
% make the filter window much wider than the narrowest feature we are
% interested in, or we'll smooth out those features too much.
window  = ceil(velWindow/1000*fs);
% number of filter taps
ntaps   = 2*ceil(window)-1;
% polynomial order
pn = 2;
% differentiation order
dn = 1;

tempV = [data.azi data.ele];
if pn < ntaps
    % smoothed deriv
    tempV = -savitzkyGolayFilt(tempV,pn,dn,ntaps) * fs;
else
    % numerical deriv
    tempV   = diff(tempV,1,1);
    % make same length as position trace by repeating first sample
    tempV   = tempV([1 1:end],:) * fs;
end
% indicate too small window by coloring spinner red
if isfield(hm.UserData.ui,'setting')
    obj = findobj(hm.UserData.ui.setting.panel.UserData.comps,'Tag','LWSpinner');
    obj = obj.Editor().getTextField().getBackground;
    clr = [obj.getRed obj.getGreen obj.getBlue]./255;
    
    obj = findobj(hm.UserData.ui.setting.panel.UserData.comps,'Tag','SGSpinner');
    if pn >= ntaps
        clr(2:3) = .5;
    end
    obj.Editor().getTextField().setBackground(javax.swing.plaf.ColorUIResource(clr(1),clr(2),clr(3)));
end

% Calculate eye velocity and acceleration straightforwardly by applying
% Pythagoras' theorem. This gives us no information about the
% instantaneous axis of the eye rotation, but eye velocity is
% calculated correctly. Apply scale for velocity, as a 10� azimuth
% rotation at 0� elevation does not cover same distance as it does at
% 45� elevation: sqrt(theta_dot^2*cos^2 phi + phi_dot^2)
vel = hypot(tempV(:,1).*cosd(data.ele), tempV(:,2));
end

function doZoom(hm,evt)
ax = evt.Axes;
% set new time window size

setTimeWindow(hm,diff(ax.XLim),false);
% set new left of it
setPlotView(hm,ax.XLim(1));

% now do vertical scale. Already set by zoom, just update elements on plot
repositionFullHeightAxisAnnotations(hm,[],evt.Axes);
end

function scrollFunc(hm,~,evt)
if evt.isControlDown || evt.isShiftDown
    ax = hitTestType(hm,'axes');    % works because we have a WindowButtonMotionFcn installed
    
    if ~isempty(ax) && any(ax==hm.UserData.plot.ax)
        axIdx = find(hm.UserData.plot.ax==ax,1);
        posInDat = ax.CurrentPoint(1,1:2);
        
        if evt.isControlDown
            % zoom time axis
            % get wheel rotation (1: top of wheel toward user, -1 top of wheel
            % away from user). Toward will be zoom in, away zoom out
            zoomFac = 1-evt.getPreciseWheelRotation*.05;
            
            % determine new timeWindow
            setTimeWindow(hm,min(zoomFac*hm.UserData.plot.timeWindow,hm.UserData.time.endTime),false);
            % determine left of window such that time under cursor does not
            % move
            bottom = max(posInDat(1)-(posInDat(1)-ax.XLim(1))*zoomFac,0);
            
            % apply new limits
            setPlotView(hm,bottom);
        else
            % zoom value axis
            
            % get current range
            range = diff(ax.YLim);
            
            % get wheel rotation (1: top of wheel toward user, -1 top of wheel
            % away from user). Toward will be zoom in, away zoom out
            zoomFac = 1-evt.getPreciseWheelRotation*.1;
            
            % determine new range of visible values
            newRange = zoomFac*range;
            
            % determine new value limits of axis such that value under
            % cursor does not move
            bottom = posInDat(2)-(posInDat(2)-ax.YLim(1))*zoomFac;
            if ismember(ax.Tag,{'vel','pup'})
                % make sure we don't go below zero where that makes no
                % sense
                bottom = max(bottom,0);
            end
            
            % apply new limits
            ax.YLim = bottom+[0 newRange];
            
            % fix up elements on axis that should be full height
            repositionFullHeightAxisAnnotations(hm,axIdx,ax);
        end
    end
end
end

function repositionFullHeightAxisAnnotations(hm,axIdx,ax)
if nargin<3
    ax = hm.UserData.plot.ax(axIdx);
elseif isempty(axIdx)
    axIdx = find(hm.UserData.plot.ax==ax);
end
% also scale time indicator to always fill whole axis
hm.UserData.plot.timeIndicator(axIdx).YData = ax.YLim;
end

function icon = getIcon(gfx,icon)
% consume any transform operations from its name
transform = '';
while ismember(icon(1),{'|','-','>','<'})
    transform = [transform icon(1)]; %#ok<AGROW>
    icon(1)=[];
end

% get icon
icon = gfx.(icon);

% apply transforms
while ~isempty(transform)
    switch transform(1)
        case '|'
            icon = flip(icon,2);
        case '-'
            icon = flip(icon,1);
        case '>'
            % rotate clockwise
            icon = rot90(icon,-1);
        case '<'
            % rotate counter clockwise
            icon = rot90(icon, 1);
    end
    transform(1) = [];
end
end

function createSettings(hm)
% settings area
width = min(335,hm.UserData.vid.ax(1).Position(3)-20);
height= min(230,hm.UserData.ui.VCR.but(1).Position(2)-20);
% center it
off = [hm.UserData.vid.ax(1).Position(3) hm.UserData.ui.VCR.but(1).Position(2)-hm.UserData.plot.axRect(end,2)]./2-[width height]./2 + [0 hm.UserData.plot.axRect(end,2)];
panelPos = [hm.UserData.vid.ax(1).Position(1)+off(1) off(2) width height];
hm.UserData.ui.setting.panel = uipanel('Units','pixels','Position',panelPos, 'title','Settings');
% pos is wanted innerPosition. scale outerPosition
off = panelPos-hm.UserData.ui.setting.panel.InnerPosition;
panelPos(3:4) = panelPos(3:4)+off(3:4);
panelPos(1:2) = panelPos(1:2)-(off(1:2)+off(3:4)/2);
hm.UserData.ui.setting.panel.Position = panelPos;

% make a bunch of components. store them in comps
parent = hm.UserData.ui.setting.panel;
c=0;
% 1. SG filter
c=c+1;
SGPos       = [140 parent.InnerPosition(4)-5-20 60 20];
ts          = 1000/hm.UserData.data.eye.fs;
jModel      = javax.swing.SpinnerNumberModel(hm.UserData.settings.plot.SGWindowVelocity,ts,ts*2000,ts);
jSpinner    = com.mathworks.mwswing.MJSpinner(jModel);
comps(c)    = uicomponent(jSpinner,'Parent',parent,'Units','pixels','Position',SGPos,'Tag','SGSpinner');
comps(c).StateChangedCallback = @(hndl,evt) changeSGCallback(hm,hndl,evt);
jEditor     = javaObject('javax.swing.JSpinner$NumberEditor', comps(c).JavaComponent, '##0 ms ');
comps(c).JavaComponent.setEditor(jEditor);

c=c+1;
jLabel      = com.mathworks.mwswing.MJLabel('Savitzky-Golay window');
jLabel.setLabelFor(comps(c-1).JavaComponent);
jLabel.setToolTipText('window length of Savitzky-Golay differentiation filter');
comps(c)    = uicomponent(jLabel,'Parent',parent,'Units','pixels','Position',[10,SGPos(2),SGPos(1)-10,SGPos(4)],'Tag','SGSpinnerLabel');

% 2 separator
c=c+1;
sepPos      = [10 SGPos(2)-10 215 1];
jSep        = javax.swing.JSeparator(javax.swing.SwingConstants.HORIZONTAL);
comps(c)    = uicomponent(jSep,'Parent',parent,'Units','pixels','Position',sepPos);

% 3 plot rearranger
% 3.1 labels
butSz       = [20 20];
arrangerSz  = [80 104];

c=c+1;
lblPos      = [10, sepPos(2)-20-5, parent.InnerPosition(3)-20, 20];
jLabel      = com.mathworks.mwswing.MJLabel('Plot order and shown axes');
comps(c)    = uicomponent(jLabel,'Parent',parent,'Units','pixels','Position',lblPos,'Tag','plotArrangerLabel');

c=c+1;
lblPos      = [10+butSz(1)+5, lblPos(2)-20-3, arrangerSz(1), 20];
jLabel      = com.mathworks.mwswing.MJLabel('Shown');
comps(c)    = uicomponent(jLabel,'Parent',parent,'Units','pixels','Position',lblPos,'Tag','plotArrangerLabel');

c=c+1;
lblPos      = [10+butSz(1)+5+arrangerSz(1)+5+butSz(1)+5, lblPos(2), arrangerSz(1), 20];
jLabel      = com.mathworks.mwswing.MJLabel('Hidden');
comps(c)    = uicomponent(jLabel,'Parent',parent,'Units','pixels','Position',lblPos,'Tag','plotArrangerLabel');

% 3.2 listbox
c=c+1;
arrangerPos = [10+butSz(1)+5 lblPos(2)-arrangerSz(2) arrangerSz];
listItems   = {hm.UserData.plot.ax.Tag};
comps(c)    = uicomponent('Style','listbox', 'Parent', parent,'Units','pixels','Position',arrangerPos, 'String',listItems,'Tag','plotArrangerShown','Max',2,'Min',0,'Value',[]);
listbox     = comps(c);

% 3.3 listbox
c=c+1;
arrangerPosJ= [arrangerPos(1)+arrangerPos(3)+5+butSz(1)+5 arrangerPos(2) arrangerSz];
listItems   = {};
comps(c)    = uicomponent('Style','listbox', 'Parent', parent,'Units','pixels','Position',arrangerPosJ, 'String',listItems,'Tag','plotArrangerHidden','Max',2,'Min',0,'Value',[]);
listboxJail = comps(c);


% 3.4 buttons
butMargin   = 4;
butPosBase  = [10 lblPos(2)-2-arrangerPos(3)/2];
gfx         = load('icons');
c=c+1;
icon        = getIcon(gfx,'<jump_to');
comps(c)    = uicontrol('Style','pushbutton','Tag','moveUp','Position',[butPosBase(1) butPosBase(2)+butMargin/2 butSz],...
    'Parent',parent,'TooltipString','move selected up','CData',icon,'Callback',@(~,~,~) movePlot(hm,listbox,-1));

c=c+1;
icon        = getIcon(gfx,'<-jump_to');
comps(c)    = uicontrol('Style','pushbutton','Tag','moveDown','Position',[butPosBase(1) butPosBase(2)-butMargin/2-butSz(2) butSz],...
    'Parent',parent,'TooltipString','move selected down','CData',icon,'Callback',@(~,~,~) movePlot(hm,listbox,1));


butPosBase  = [arrangerPos(1)+arrangerPos(3)+5 lblPos(2)-2-arrangerPos(3)/2];
c=c+1;
icon        = getIcon(gfx,'ffwd_default');
comps(c)    = uicontrol('Style','pushbutton','Tag','moveUp','Position',[butPosBase(1) butPosBase(2)+butMargin/2 butSz],...
    'Parent',parent,'TooltipString','move selected up','CData',icon,'Callback',@(~,~,~) jailAxis(hm,listbox,listboxJail,'jail'));

c=c+1;
icon        = getIcon(gfx,'rewind_default');
comps(c)    = uicontrol('Style','pushbutton','Tag','moveDown','Position',[butPosBase(1) butPosBase(2)-butMargin/2-butSz(2) butSz],...
    'Parent',parent,'TooltipString','move selected down','CData',icon,'Callback',@(~,~,~) jailAxis(hm,listbox,listboxJail,'restore'));

% 4 separator
c=c+1;
sepPos      = [10 arrangerPos(2)-10 215 1];
jSep        = javax.swing.JSeparator(javax.swing.SwingConstants.HORIZONTAL);
comps(c)    = uicomponent(jSep,'Parent',parent,'Units','pixels','Position',sepPos);

% 5 plotLineWidth
c=c+1;
LWPos       = [140 sepPos(2)-sepPos(4)-5-20 60 20];
jModel      = javax.swing.SpinnerNumberModel(hm.UserData.settings.plot.lineWidth,.5,5,.5);
jSpinner    = com.mathworks.mwswing.MJSpinner(jModel);
comps(c)    = uicomponent(jSpinner,'Parent',parent,'Units','pixels','Position',LWPos,'Tag','LWSpinner');
comps(c).StateChangedCallback = @(hndl,evt) changeLineWidth(hm,hndl,evt);
jEditor     = javaObject('javax.swing.JSpinner$NumberEditor', comps(c).JavaComponent, '##0.0 pix ');
comps(c).JavaComponent.setEditor(jEditor);

c=c+1;
jLabel      = com.mathworks.mwswing.MJLabel('Plot line width');
jLabel.setLabelFor(comps(c-1).JavaComponent);
jLabel.setToolTipText('Line width for the plotted data');
comps(c)    = uicomponent(jLabel,'Parent',parent,'Units','pixels','Position',[10,LWPos(2),LWPos(1)-10,LWPos(4)],'Tag','LWSpinnerLabel');

% 6 separator
c=c+1;
sepPos      = [arrangerPosJ(1)+arrangerPosJ(3)+10 10 1 parent.InnerPosition(4)-20];
jSep        = javax.swing.JSeparator(javax.swing.SwingConstants.VERTICAL);
comps(c)    = uicomponent(jSep,'Parent',parent,'Units','pixels','Position',sepPos);

% 7 current time
c=c+1;
CTPos       = [sepPos(1)+10 parent.InnerPosition(4)-5-20-5-20 85 20];
% do this complicated way to take timezone effects into account..
% grr... Setting the timezone of the formatter fixes the display, but
% seems to make the spinner unsettable
cal=java.util.GregorianCalendar.getInstance();
cal.clear();
cal.set(1970, cal.JANUARY, 1, 0, 0);
hm.UserData.time.timeSpinnerOffset = cal.getTime().getTime();   % need to take this offset for the time object into account
startDate   = java.util.Date(0+hm.UserData.time.timeSpinnerOffset);
endDate     = java.util.Date(round(hm.UserData.time.endTime*1000)+hm.UserData.time.timeSpinnerOffset);
% now use these adjusted start and end dates for the spinner
jModel      = javax.swing.SpinnerDateModel(startDate,startDate,endDate,java.util.Calendar.SECOND);
% NB: spinning the second field is only an initial state! For each spin
% action, the current caret position is taken and the field it is in is
% spinned
jSpinner    = com.mathworks.mwswing.MJSpinner(jModel);
comps(c)    = uicomponent(jSpinner,'Parent',parent,'Units','pixels','Position',CTPos,'Tag','CTSpinner');
jEditor     = javaObject('javax.swing.JSpinner$DateEditor', comps(c).JavaComponent, 'HH:mm:ss.SSS ');
jEditor.getTextField.setHorizontalAlignment(javax.swing.JTextField.RIGHT);
formatter   = jEditor.getTextField().getFormatter();
formatter.setAllowsInvalid(false);
formatter.setOverwriteMode(true);
comps(c).JavaComponent.setEditor(jEditor);
comps(c).StateChangedCallback = @(hndl,evt) setCurrentTimeSpinnerCallback(hm,hndl.Value);

c=c+1;
LblPos      = [CTPos(1),CTPos(2)+5+20,CTPos(1)-10,CTPos(4)];
jLabel      = com.mathworks.mwswing.MJLabel('Current time');
jLabel.setLabelFor(comps(c-1).JavaComponent);
jLabel.setToolTipText('<html>Display and change current time.<br>Spinner button change the field that the caret is in.<br>Typing overwrites values and is committed with [enter]</html>');
comps(c)    = uicomponent(jLabel,'Parent',parent,'Units','pixels','Position',LblPos,'Tag','CTSpinnerLabel');

% 8 current window
c=c+1;
CWPos       = [sepPos(1)+10 CTPos(2)-15-20-5-20 85 20];
jModel      = javax.swing.SpinnerNumberModel(hm.UserData.plot.timeWindow,0,hm.UserData.time.endTime,1);
jSpinner    = com.mathworks.mwswing.MJSpinner(jModel);
comps(c)    = uicomponent(jSpinner,'Parent',parent,'Units','pixels','Position',CWPos,'Tag','TWSpinner');
comps(c).StateChangedCallback = @(hndl,evt) setTimeWindow(hm,hndl.getValue,true);
jEditor     = javaObject('javax.swing.JSpinner$NumberEditor', comps(c).JavaComponent, '###0.00 s ');
comps(c).JavaComponent.setEditor(jEditor);

c=c+1;
LblPos      = [CWPos(1),CWPos(2)+5+20,CWPos(1)-10,CWPos(4)];
jLabel      = com.mathworks.mwswing.MJLabel('Time window');
jLabel.setLabelFor(comps(c-1).JavaComponent);
comps(c)    = uicomponent(jLabel,'Parent',parent,'Units','pixels','Position',LblPos,'Tag','TWSpinnerLabel');

% 9 playback speed
c=c+1;
CPPos       = [sepPos(1)+10 CWPos(2)-15-20-5-20 85 20];
jModel      = javax.swing.SpinnerNumberModel(1,0,16,0.001);
jSpinner    = com.mathworks.mwswing.MJSpinner(jModel);
comps(c)    = uicomponent(jSpinner,'Parent',parent,'Units','pixels','Position',CPPos,'Tag','PSSpinner');
comps(c).StateChangedCallback = @(hndl,evt) setPlaybackSpeed(hm,hndl);
jEditor     = javaObject('javax.swing.JSpinner$NumberEditor', comps(c).JavaComponent, '###0.000 x ');
comps(c).JavaComponent.setEditor(jEditor);

c=c+1;
LblPos      = [CPPos(1),CPPos(2)+5+20,CPPos(1)-10,CPPos(4)];
jLabel      = com.mathworks.mwswing.MJLabel('Playback speed');
jLabel.setLabelFor(comps(c-1).JavaComponent);
comps(c)    = uicomponent(jLabel,'Parent',parent,'Units','pixels','Position',LblPos,'Tag','PSSpinnerLabel');


hm.UserData.ui.setting.panel.UserData.comps = comps;
end

function changeSGCallback(hm,hndl,~)
% get new value
ts = 1000/hm.UserData.data.eye.fs;
newVal = round(hndl.getValue/ts)*ts;

% if changed, update data
if newVal~=hm.UserData.settings.plot.SGWindowVelocity
    % set new value
    hm.UserData.settings.plot.SGWindowVelocity = newVal;
    
    % refilter data
    velL = getVelocity(hm,hm.UserData.data.eye. left,hm.UserData.settings.plot.SGWindowVelocity,hm.UserData.data.eye.fs);
    velR = getVelocity(hm,hm.UserData.data.eye.right,hm.UserData.settings.plot.SGWindowVelocity,hm.UserData.data.eye.fs);
    
    % update plot
    ax = findobj(hm.UserData.plot.ax,'Tag','vel');
    left  = findobj(ax.Children,'Tag','data|left');
    left.YData = velL;
    right = findobj(ax.Children,'Tag','data|right');
    right.YData = velR;
end
end

function changeLineWidth(hm,hndl,~)
% get new value
newVal = hndl.getValue;

% if changed, update data
if newVal~=hm.UserData.settings.plot.lineWidth
    % set new value
    hm.UserData.settings.plot.lineWidth = newVal;
    
    % update plots
    children = findall(cat(1,hm.UserData.plot.ax.Children),'Type','line');
    children = children(contains({children.Tag},'data|'));
    [children.LineWidth] = deal(newVal);
end
end

function movePlot(hm,listbox,dir)
selected = listbox.Value;
list = listbox.String;

items = 1:length(list);
toMove = selected;
cantMove = [];
qSel= ismember(items,toMove);
% prune unmovable ones
if dir==-1 && qSel(1)
    qSel(1:find(~qSel,1)-1) = false;
    cantMove = setxor(find(qSel),toMove);
    toMove = find(qSel);
end
if dir==1 && qSel(end)
    qSel(find(~qSel,1,'last')+1:end) = false;
    cantMove = setxor(find(qSel),toMove);
    toMove = find(qSel);
end
if isempty(toMove)
    return
end

% find new position in series
if dir==-1
    for m=toMove
        items(m-1:m) = fliplr(items(m-1:m));
    end
else
    for m=fliplr(toMove)
        items(m:m+1) = fliplr(items(m:m+1));
    end
end

% move the plot axes, update info about them in hm
moveThePlots(hm,items);

% update this listbox and its selection
listbox.String = list(items);
listbox.Value = sort([find(ismember(items,toMove)) cantMove]);
end

function jailAxis(hm,listbox,listboxJail,action)

if strcmp(action,'jail')
    shownList   = listbox.String;
    selected    = listbox.Value;
    % first move plots to remove from view to end
    items       = 1:length(shownList);
    qSel        = ismember(items,selected);
    shown       = shownList(~qSel);
    hide        = shownList( qSel);
    items       = [items(~qSel) items(qSel)];
    moveThePlots(hm,items);
    % determine new plot positions
    setupPlots(hm,shown,length(hm.UserData.plot.ax))
    % update axes
    newPos = num2cell(hm.UserData.plot.axPos,2);
    nShown = length(shown);
    nHiding= length(hide);
    [hm.UserData.plot.ax(1:nShown)    .Position]= newPos{:};
    for p=nShown+[1:nHiding]
        hndls = [hm.UserData.plot.ax(p); hm.UserData.plot.ax(p).Children];
        [hndls.Visible] = deal('off');
    end
    % set axis labels and ticks for new lowest plot
    hm.UserData.plot.ax(nShown).XTickLabelMode = 'auto';
    hm.UserData.plot.ax(nShown).XLabel.String = hm.UserData.plot.ax(end).XLabel.String;
    % update list boxes
    listbox.Value       = [];    % deselect
    listbox.String      = shown; % leftovers
    listboxJail.String  = [hide; listboxJail.String];
    listboxJail.Value   = [1:nHiding];
else
    jailList = listboxJail.String;
    shownList= listbox    .String;
    selected = listboxJail.Value;
    % get those to show again
    toShow   = jailList(selected);
    nShown   = length(shownList);
    % assumption: hidden panels are in the list of axes in the same order
    % as in the jail listbox
    itemsShown  = 1:length(shownList);
    itemsToShow = 1:length(jailList);
    qSel        = ismember(itemsToShow,selected);
    items       = [itemsShown find(qSel)+nShown find(~qSel)+nShown];
    % move panels into place
    moveThePlots(hm,items);
    % determine new plot positions
    toShow      = [shownList; toShow];
    setupPlots(hm,toShow,length(hm.UserData.plot.ax));
    % update axes
    newPos    = num2cell(hm.UserData.plot.axPos,2);
    nShownNew = length(toShow);
    [hm.UserData.plot.ax(1:nShownNew).Position]= newPos{:};
    for p=nShown+1:nShownNew
        hndls = [hm.UserData.plot.ax(p); hm.UserData.plot.ax(p).Children];
        [hndls.Visible] = deal('on');
    end
    % set axis labels and ticks for new lowest plot
    hm.UserData.plot.ax(nShown).XTickLabel = {};
    hm.UserData.plot.ax(nShownNew).XTickLabelMode = 'auto';
    hm.UserData.plot.ax(nShownNew).XLabel.String = hm.UserData.plot.ax(nShown).XLabel.String;
    hm.UserData.plot.ax(nShown).XLabel.String = '';
    % update list boxes
    listboxJail.Value   = [];    % deselect
    listboxJail.String  = jailList(~qSel);
    listbox.String      = toShow;
    listbox.Value       = nShown+1:nShownNew;
end
% reposition axis labels (as vertical height of visible axes just changed)
fixupAxisLabels(hm)

end

function moveThePlots(hm,newOrder)
if iscell(newOrder)
    currOrder = {hm.UserData.plot.ax.Tag};
    newOrder = cellfun(@(x) find(strcmp(x,currOrder),1),newOrder);
end
if length(newOrder)<length(hm.UserData.plot.ax)
    newOrder = [newOrder length(newOrder)+1:length(hm.UserData.plot.ax)];
end
nVisible = sum(~isnan(hm.UserData.plot.axPos(:,1)));
% check if bottom one is moved and we thus need to give another plot the
% axis limits
if newOrder(nVisible)~=nVisible
    % remove tick lables from current end
    hm.UserData.plot.ax(nVisible).XTickLabel = {};
    % add tick labels to new end
    hm.UserData.plot.ax(newOrder(nVisible)).XTickLabelMode = 'auto';
    % also deal with axis title
    hm.UserData.plot.ax(newOrder(nVisible)).XLabel.String = hm.UserData.plot.ax(nVisible).XLabel.String;
    hm.UserData.plot.ax(nVisible).XLabel.String = '';
end

% get axis positions, and transplant
thePlots = {hm.UserData.plot.ax(1:nVisible).Tag};
setupPlots(hm,thePlots(newOrder(1:nVisible)),length(hm.UserData.plot.ax));
for a=1:nVisible
    if a~=newOrder(a)
        hm.UserData.plot.ax(newOrder(a)).Position = hm.UserData.plot.axPos(a,:);
    end
end

% reorder handles and other plot attributes
assert(isempty(setxor(fieldnames(hm.UserData.plot),{'timeWindow','ax','defaultValueScale','axPos','axRect','timeIndicator','margin','zoom'})),'added new fields, check if need to reorder')
hm.UserData.plot.ax                 = hm.UserData.plot.ax(newOrder);
hm.UserData.plot.timeIndicator      = hm.UserData.plot.timeIndicator(newOrder);
hm.UserData.plot.defaultValueScale  = hm.UserData.plot.defaultValueScale(:,newOrder);
hm.UserData.plot.axPos              = hm.UserData.plot.axPos(newOrder,:);
hm.UserData.plot.axRect             = hm.UserData.plot.axRect(newOrder,:);
end

function resetPlotValueLimits(hm)
for p=1:length(hm.UserData.plot.ax)
    if hm.UserData.plot.ax(p).YLim ~= hm.UserData.plot.defaultValueScale(:,p)
        hm.UserData.plot.ax(p).YLim = hm.UserData.plot.defaultValueScale(:,p);
        repositionFullHeightAxisAnnotations(hm,p);
    end
end
end

function sliderClick(hm,hndl,evt)
% click stop playback
startStopPlay(hm,0);

p = evt.getPoint();
h=hndl.Height;
newVal = hndl.UI.valueForXPosition(p.x);

% DEBUG check that i got figuring out of left and right edge of slider
% correct (Need to put hm into the function!)
% d=p.x-hm.UserData.ui.VCR.slider.left
% hm.UserData.ui.VCR.slider.right
% round(d/(hm.UserData.ui.VCR.slider.right-hm.UserData.ui.VCR.slider.left)*hndl.Maximum())

% check if on active part of slider, or on the inactive part underneath
if p.y<=h/2
    % active part: adjust where the window indicator just jumped
    % get current values and see which we are closest too
    d = abs(newVal-[hndl.LowValue hndl.HighValue]);
    if d(2)<d(1)
        hndl.setHighValue(newVal);
    else
        hndl.setLowValue(newVal);
    end
else
    % inactive part: update current time
    setCurrentTime(hm,newVal/hm.UserData.ui.VCR.slider.fac);
end
end

function sliderChange(hm,hndl,~)
% get expected values
expectedLow     = floor(hm.UserData.plot.ax(1).XLim(1)*hm.UserData.ui.VCR.slider.fac);
expectedExtent  = floor(hm.UserData.plot.timeWindow*hm.UserData.ui.VCR.slider.fac);
extent          = max(hndl.Extent,1); % make sure not zero

% if not as expected, set
if hndl.LowValue~=expectedLow || extent~=expectedExtent
    setTimeWindow(hm,double(extent)/hm.UserData.ui.VCR.slider.fac,false);
    setPlotView(hm,double(hndl.LowValue)/hm.UserData.ui.VCR.slider.fac);
end
end

function doPostInit(hm)
% setup line to indicate time on slider under video. Take into account DPI
% scaling, reading from the slider's position is done in true screen space
px1 = arrayfun(@(x) hm.UserData.ui.VCR.slider.jComp.UI.valueForXPosition(x),5:40);
hm.UserData.ui.VCR.slider.left = (  find(diff(px1),1)+5-1)/hm.UserData.ui.DPIScale;
w=hm.UserData.ui.VCR.slider.jComp.Width;
px2 = arrayfun(@(x) hm.UserData.ui.VCR.slider.jComp.UI.valueForXPosition(x),w-[5:40]);
hm.UserData.ui.VCR.slider.right= (w-find(diff(px2),1)-5+1)/hm.UserData.ui.DPIScale;

% lets install our own mouse scroll listener. Yeah, done in a tricky way as
% i want the java event which gives axes to modifiers and cursor location.
% the matlab event from the figure is useless for me here
jFrame = get(gcf,'JavaFrame');
j=handle(jFrame.fHG2Client.getAxisComponent, 'CallbackProperties');
j.MouseWheelMovedCallback = @(hndl,evt) scrollFunc(hm,hndl,evt);

% UI for zooming. Create zoom object now. If doing it before the above,
% then, for some reason the MouseWheelMovedCallback and all other callbacks
% are not available...
hm.UserData.plot.zoom.obj                   = zoom();
hm.UserData.plot.zoom.obj.ActionPostCallback= @(~,evt)doZoom(hm,evt);
% disallow zoom for legend
setAllowAxesZoom(hm.UserData.plot.zoom.obj,hm.UserData.ui.signalLegend,false);
% timer for switching zoom mode back off
hm.UserData.plot.zoom.timer = timer('ExecutionMode', 'singleShot', 'TimerFcn', @(~,~) startZoom(hm), 'StartDelay', 10/1000);

% fix all y-axis labels to same distance
fixupAxisLabels(hm);
end

function fixupAxisLabels(hm)
% fix all y-axis labels to same distance
yl=[hm.UserData.plot.ax.YLabel];
[yl.Units] = deal('pixels');
pos = cat(1,yl.Position);
pos(:,1) = min(pos(:,1));                       % set to furthest
pos(:,2) = hm.UserData.plot.axPos(1,end)/2;     % center vertically
pos = num2cell(pos,2);
[yl.Position] = pos{:};
end

function KillCallback(hm,~)
% delete timers
try
    stop(hm.UserData.time.mainTimer);
    delete(hm.UserData.time.mainTimer);
catch
    % carry on
end
try
    stop(hm.UserData.plot.zoom.timer);
    delete(hm.UserData.plot.zoom.time);
catch
    % carry on
end

% clean up videos
try
    for p=1:numel(hm.UserData.vid.objs)
        try
            delete(hm.UserData.vid.objs(p).StreamHandle);
        catch
            % carry on
        end
    end
catch
    % carry on
end

% clean up UserData
hm.UserData = [];

% execute default
closereq();
end

function KeyPress(hm,evt,evt2)
if nargin>2
    theChar = evt2.getKeyCode;
    % convert if needed (arrow keys)
    switch theChar
        case 37
            theChar = 28;
        case 39
            theChar = 29;
        case 65
            theChar = 97;
        case 68
            theChar = 100;
        case 82
            theChar = 18;
        case 90
            theChar = 122;
        otherwise
            % evt2.get
    end
    modifiers = {};
    if evt2.isControlDown
        modifiers{end+1} = 'control';
    end
else
    theChar     = evt.Character;
    modifiers   = evt.Modifier;
end
if ~isempty(theChar)
    switch double(theChar)
        case 27
            % escape
            if hm.UserData.ui.grabbedTime
                % if dragging time, cancel it
                hm.UserData.time.currentTime = hm.UserData.ui.grabbedTimeLoc;
                endDrag(hm);
            elseif strcmp(hm.UserData.plot.zoom.obj.Enable,'on')
                % if in zoom mode, exit
                hm.UserData.plot.zoom.obj.Enable = 'off';
            end
        case {28,97}
            % left arrow / a key: previous window
            jumpWin(hm,-1);
        case {29,100}
            % right arrow / d key: next window
            jumpWin(hm, 1);
        case 32
            % space bar
            startStopPlay(hm,-1);
        case 18
            % control+r gives this code (and possibly other things too
            % if control also pressed), reset plot axes
            if any(strcmp(modifiers,'control'))
                resetPlotValueLimits(hm)
            end
        case 122
            % z pressed: engage (or disengage) zoom
            if strcmp(hm.UserData.plot.zoom.obj.Enable,'off')
                start(hm.UserData.plot.zoom.timer);
                % this timer calls the startZoom function. For some reason,
                % when making the calls in that function here, in the
                % keypress callback, the z leaks through to matlab's
                % command prompt, which then steals focus from the GUI and
                % pops up over it... So use the timer to make the calls to
                % enable zoom outside of the keypress callback...
            else
                stop(hm.UserData.plot.zoom.timer);
                hm.UserData.plot.zoom.obj.Enable = 'off';
            end
    end
end
end

function startZoom(hm)
hm.UserData.plot.zoom.obj.Enable = 'on';
% entering zoom mode switches off callbacks. Reenable them
% http://undocumentedmatlab.com/blog/enabling-user-callbacks-during-zoom-pan
hManager = uigetmodemanager(hm);
[hManager.WindowListenerHandles.Enabled] = deal(false);
hm.WindowKeyPressFcn = @KeyPress;
end

function MouseMove(hm,~)
axisHndl = hitTestType(hm,'axes');
if ~isempty(axisHndl) && any(axisHndl==hm.UserData.plot.ax)
    % ok, hovering on axis. Now process possible hover, drag and scroll
    % actions
    mPosX = axisHndl.CurrentPoint(1,1);
    lineHndl = hitTestType(hm,'line');
    if ~isnan(hm.UserData.ui.scrollRef(1))
        % keep ref point under the cursor: scroll the window
        mPosXY = hm.UserData.ui.scrollRefAx.CurrentPoint(1,1:2);
        % keep ref point under the cursor: scroll the window
        left = hm.UserData.ui.scrollRefAx.XLim(1) - (mPosXY(1)-hm.UserData.ui.scrollRef(1));
        setPlotView(hm,left);
        % and now vertically
        vertOff = mPosXY(2)-hm.UserData.ui.scrollRef(2);
        hm.UserData.ui.scrollRefAx.YLim = hm.UserData.ui.scrollRefAx.YLim-vertOff;
        repositionFullHeightAxisAnnotations(hm,[],hm.UserData.ui.scrollRefAx);
    elseif hm.UserData.ui.grabbedTime
        % dragging, move timelines
        setCurrentTime(hm,mPosX,true,false);    % don't do a full time update, loading in new video frames is too slow
        updateTimeLines(hm);
    elseif isempty(lineHndl) && hm.UserData.ui.hoveringTime
        % we're no longer hovering time line or marker
        checkCursorHover(hm,lineHndl);
    elseif ~isempty(lineHndl) && contains(lineHndl.Tag,'timeIndicator')
        % we're hovering time line
        checkCursorHover(hm,lineHndl);
    end
else
    if ~isnan(hm.UserData.ui.scrollRef(1))
        % we may be out of the axis, but we're still scrolling. asking an
        % axis for current point should still work, so we can keep
        % scrolling
        mPosXY = hm.UserData.ui.scrollRefAx.CurrentPoint(1,1:2);
        % keep ref point under the cursor: scroll the window
        left = hm.UserData.ui.scrollRefAx.XLim(1) - (mPosXY(1)-hm.UserData.ui.scrollRef(1));
        setPlotView(hm,left);
        % and now vertically
        vertOff = mPosXY(2)-hm.UserData.ui.scrollRef(2);
        hm.UserData.ui.scrollRefAx.YLim = hm.UserData.ui.scrollRefAx.YLim-vertOff;
        repositionFullHeightAxisAnnotations(hm,[],hm.UserData.ui.scrollRefAx);
    elseif hm.UserData.ui.hoveringTime
        % exited axes, remove hover cursor
        hm.UserData.ui.hoveringTime = false;
        setHoverCursor(hm);
    elseif hm.UserData.ui.grabbedTime
        % find if to left or to right of axis
        mPosX = hm.CurrentPoint(1); % this in now in pixels in the figure window
        % since all axes are aligned, check against any left bound
        if mPosX<hm.UserData.plot.axRect(1,1)
            % on left of axis
            setCurrentTime(hm,hm.UserData.plot.ax(1).XLim(1),true);
        else
            % on right of axis
            setCurrentTime(hm,hm.UserData.plot.ax(1).XLim(2),true);
        end
        endDrag(hm);
    end
end
end

function setHoverCursor(hm)
if hm.UserData.ui.hoveringTime
    setptr(hm,'lrdrag');
else
    setptr(hm,'arrow');
end
end

function checkCursorHover(hm,lineHndl)
if nargin<2
    lineHndl = hitTestType(hm,'line');
end

if ~isempty(lineHndl) && contains(lineHndl.Tag,'timeIndicator')
    % we're hovering time line
    hm.UserData.ui.hoveringTime = true;
else
    % no hovering at all
    hm.UserData.ui.hoveringTime = false;
end
% change cursor
setHoverCursor(hm);
end

function MouseClick(hm,~)
if strcmp(hm.SelectionType,'normal')
    if hm.UserData.ui.hoveringTime
        % start drag time line
        hm.UserData.ui.grabbedTime      = true;
        hm.UserData.ui.grabbedTimeLoc   = hm.UserData.time.currentTime;
    end
elseif strcmp(hm.SelectionType,'extend')
    % nothing for shift-click
elseif strcmp(hm.SelectionType,'alt')
    % control-click or right mouse click: scroll time axis
    ax = hitTestType(hm,'axes');
    if ~isempty(ax) && any(ax==hm.UserData.plot.ax)
        hm.UserData.ui.scrollRef    = ax.CurrentPoint(1,1:2);
        hm.UserData.ui.scrollRefAx  = ax;
        % if we were, now we're no longer hovering time line
        if hm.UserData.ui.hoveringTime
            hm.UserData.ui.hoveringTime = false;
            % change cursor
            setHoverCursor(hm);
        end
    end
elseif strcmp(hm.SelectionType,'open')
    % double click: set current time to clicked location
    ax = hitTestType(hm,'axes');
    if ~isempty(ax) && any(ax==hm.UserData.plot.ax)
        mPosX = ax.CurrentPoint(1);
        hm.UserData.ui.justMovedTimeByMouse = true;
        setCurrentTime(hm,mPosX,true);
        % change cursor to hovering, as we will be, unless user moves mouse
        % again in which case mousemove will take care of clearing this
        % again
        hm.UserData.ui.hoveringTime = true;
        % change cursor
        setHoverCursor(hm);
    end
end
end

function MouseRelease(hm,~)
if hm.UserData.ui.grabbedTime
    endDrag(hm);
elseif ~isnan(hm.UserData.ui.scrollRef(1))
    hm.UserData.ui.scrollRef = [nan nan];
    hm.UserData.ui.scrollRefAx = matlab.graphics.GraphicsPlaceholder;
end
end

function endDrag(hm,doFullUpdate)
% end drag time line
if hm.UserData.ui.grabbedTime
    hm.UserData.ui.grabbedTime          = false;
    hm.UserData.ui.justMovedTimeByMouse = true;
    hm.UserData.ui.grabbedTimeLoc       = nan;
    % do full time update
    if nargin<2 || doFullUpdate
        updateTime(hm);
    end
end
% update cursors (check for hovers and adjusts cursor if needed)
checkCursorHover(hm);
end

function startStopPlay(hm,desiredState,src)
% input:
% -1 toggle
%  0  stop playback
%  1 start playback

if desiredState==-1
    % toggle
    desiredState = ~hm.UserData.ui.VCR.state.playing;
else
    % cast to bool
    desiredState = logical(desiredState);
end

if desiredState==hm.UserData.ui.VCR.state.playing
    % nothing to do
    return
end

% update state
hm.UserData.ui.VCR.state.playing = desiredState;

% update icon and tooltip
idx = desiredState+1;
if nargin<3
    src = findobj(hm.UserData.ui.VCR.but,'Tag','Play');
end
src.CData         = src.UserData{1}{idx};
src.TooltipString = src.UserData{2}{idx};
drawnow

% start/stop playback
if desiredState
    % start playing
    start(hm.UserData.time.mainTimer);
    % cancel any drag (also cancels hover)
    endDrag(hm,false);
else
    % stop playing
    stop(hm.UserData.time.mainTimer);
end

if ~desiredState
    % do a final update to make sure that all things indicating time are
    % correct
    updateTime(hm);
end
end

function toggleCycle(hm,src)
% toggle
hm.UserData.ui.VCR.state.cyclePlay = ~hm.UserData.ui.VCR.state.cyclePlay;
% update tooltip
idx = hm.UserData.ui.VCR.state.cyclePlay+1;
src.TooltipString = src.UserData{1}{idx};
end

function toggleDataTrail(hm,src)
switch hm.UserData.vid.gt.Visible
    case 'on'
        hm.UserData.vid.gt.Visible = 'off';
        idx = 1;
    case 'off'
        hm.UserData.vid.gt.Visible = 'on';
        setDataTrail(hm);
        idx = 2;
end
% update tooltip
src.TooltipString = src.UserData{1}{idx};
end

function setDataTrail(hm)
firstIToShow = find(hm.UserData.data.eye.binocular.ts<=hm.UserData.plot.ax(1).XLim(1),1,'last');
lastIToShow  = find(hm.UserData.data.eye.binocular.ts<=hm.UserData.plot.ax(1).XLim(2),1,'last');
pos = hm.UserData.data.eye.binocular.gp(firstIToShow:lastIToShow,:).*hm.UserData.vid.objs(1,1).Dimensions(2:-1:1);
hm.UserData.vid.gt.XData = pos(:,1);
hm.UserData.vid.gt.YData = pos(:,2);
end

function seek(hm,step)
% stop playback
startStopPlay(hm,0);

% get new time (step is in s) and update display
setCurrentTime(hm,hm.UserData.time.currentTime+step);
end

function jumpWin(hm,dir)
% calculate step
step = dir*hm.UserData.plot.timeWindow;
% execute
left = hm.UserData.plot.ax(1).XLim(1) + step;
setPlotView(hm,left);   % clipping to time happens in here
end

function timerTick(evt,hm)
% check if timer is still supposed to be running, or if this is a stale
% tick, cancel in that case. Apparently when current timer callback is
% executing and the timer ticks again, the next callback invocation gets
% added to a queue and will also trigger. So make sure we don't do anything
% when we shouldn't
if ~hm.UserData.ui.VCR.state.playing
    return;
end

% increment time (timer may drop some events if update takes too long. take
% into account)
elapsed = etime(evt.Data.time,hm.UserData.ui.VCR.state.playLastTickTime);
hm.UserData.ui.VCR.state.playLastTickTime = evt.Data.time;
ticks   = round(elapsed/hm.UserData.time.tickPeriod);
newTime = hm.UserData.time.currentTime + hm.UserData.time.timeIncrement*ticks;

% check for cycle play within limits set by user
if hm.UserData.ui.VCR.state.cyclePlay && newTime>hm.UserData.plot.ax(1).XLim(2)
    newTime = newTime-hm.UserData.plot.timeWindow;
end

% stop play if ran out of video timeline
if newTime >= hm.UserData.time.endTime
    newTime = hm.UserData.time.endTime;
    startStopPlay(hm,0);
end

% update current time and update display
setCurrentTime(hm,newTime);

% periodically issue drawnow
hm.UserData.ui.VCR.state.cumTicks = hm.UserData.ui.VCR.state.cumTicks+ticks;
if hm.UserData.ui.VCR.state.cumTicks*hm.UserData.time.tickPeriod>.2
    start(timer('TimerFcn',@(~,~)drawnow)); % execute asynchronously so execution of this timer is not blocked
    hm.UserData.ui.VCR.state.cumTicks = 0;
end
end

function initPlayback(evt,hm)
hm.UserData.ui.VCR.state.cumTicks         = 0;
hm.UserData.ui.VCR.state.playLastTickTime = evt.Data.time;
end

function updateTime(hm)
% determine for each video what is the frame to show
for p=1:size(hm.UserData.vid.objs,2)
    switch p
        case 1
            field = 'scene';
        case 2
            field = 'eye';
    end
    frameToShow = find(hm.UserData.data.videoSync.(field).fts<=hm.UserData.time.currentTime,1,'last');
    
    % if different from currently showing frame, update
    if ~isempty(frameToShow) && hm.UserData.vid.currentFrame(p)~=frameToShow
        % show new frame
        iVideo = find(frameToShow>hm.UserData.vid.switchFrames(:,p),1,'last');
        vidFrameToShow = frameToShow;
        if iVideo>1
            vidFrameToShow = vidFrameToShow-hm.UserData.vid.switchFrames(iVideo,p);
        end
        hm.UserData.vid.im(p).CData = hm.UserData.vid.objs(iVideo,p).StreamHandle.read(vidFrameToShow);
        % update what frame we're currently showing
        hm.UserData.vid.currentFrame(p) = frameToShow;
    end
end

% update gaze marker on scene video
idxToShow = find(hm.UserData.data.eye.binocular.ts<=hm.UserData.time.currentTime,1,'last');
pos = hm.UserData.data.eye.binocular.gp(idxToShow,:).*hm.UserData.vid.objs(1,1).Dimensions(2:-1:1);
hm.UserData.vid.gm.XData = pos(1);
hm.UserData.vid.gm.YData = pos(2);

% update time indicator on data plots, and VCR line
updateTimeLines(hm);

% update visible window, move it if cursor is in last 20% (or outside
% window altogether of course
wPos        = hm.UserData.plot.ax(1).XLim(1);
qTLeft      = hm.UserData.time.currentTime<wPos;
qTimeTooFar = (hm.UserData.time.currentTime-wPos > hm.UserData.plot.timeWindow*.8) && ~hm.UserData.ui.VCR.state.cyclePlay && ~hm.UserData.ui.justMovedTimeByMouse && ~hm.UserData.ui.grabbedTime;
hm.UserData.ui.justMovedTimeByMouse  = false;
if qTLeft || qTimeTooFar
    % determine new window position:
    % if time is too far into the window, move it such that time is at .2 from left of window
    % if time is left of window, move window so it coincides with time
    if qTLeft
        left = hm.UserData.time.currentTime;
    else
        left = hm.UserData.time.currentTime-hm.UserData.plot.timeWindow*.2;
    end
    
    setPlotView(hm,left);
end

% update time spinner
currentTime = findobj(hm.UserData.ui.setting.panel.UserData.comps,'Tag','CTSpinner');
if (currentTime.Value.getTime-hm.UserData.time.timeSpinnerOffset)/1000~=hm.UserData.time.currentTime && ~hm.UserData.ui.VCR.state.playing
    currentTime.Value = java.util.Date(round(hm.UserData.time.currentTime*1000)+hm.UserData.time.timeSpinnerOffset);
end
end

function updateTimeLines(hm)
% update time indicator on data plots
[hm.UserData.plot.timeIndicator.XData] = deal(hm.UserData.time.currentTime([1 1]));

% update VCR line
timeFrac = hm.UserData.time.currentTime/hm.UserData.time.endTime;
relPos = timeFrac*(hm.UserData.ui.VCR.slider.right-hm.UserData.ui.VCR.slider.left)-hm.UserData.ui.VCR.line.jComp.Position(3)/2; % take width of indicator into account
hm.UserData.ui.VCR.line.jComp.Position(1) = hm.UserData.ui.VCR.slider.offset(1)+hm.UserData.ui.VCR.slider.left+relPos;
end

function setCurrentTimeSpinnerCallback(hm,newTime)
if hm.UserData.ui.VCR.state.playing
    % updated programmatically, ignore
    return;
end
newTime = (newTime.getTime-hm.UserData.time.timeSpinnerOffset)/1000;
if newTime~=hm.UserData.time.currentTime
    setCurrentTime(hm,newTime);
end
end

function setCurrentTime(hm,newTime,qStayWithinWindow,qUpdateTime)
if nargin<4
    qUpdateTime = true;
end
if nargin<3
    qStayWithinWindow = false;
end
% newTime should be a multiple of inter-sample-interval, and clamp it to 0
% and data length
newTime = clampTime(hm,newTime);
if qStayWithinWindow
    if newTime < hm.UserData.plot.ax(1).XLim(1)
        newTime = newTime+1/hm.UserData.data.eye.fs;
    elseif newTime > hm.UserData.plot.ax(1).XLim(2)
        newTime = newTime-1/hm.UserData.data.eye.fs;
    end
end 
hm.UserData.time.currentTime = newTime;
if qUpdateTime
    updateTime(hm);
end
end

function time = clampTime(hm,time)
% clamps to 0 and end, and rounds to nearest (ideal) sample
time = min(max(round(time*hm.UserData.data.eye.fs)/hm.UserData.data.eye.fs,0),hm.UserData.time.endTime);
end

function setTimeWindow(hm,newTime,qCallSetPlotView)
% allow window to change in steps of 1 sample, and be minimum 2 samples
% wide
newTime = max(round(newTime*hm.UserData.data.eye.fs)/hm.UserData.data.eye.fs,2/hm.UserData.data.eye.fs);
if newTime~=hm.UserData.plot.timeWindow
    hm.UserData.plot.timeWindow = newTime;
    if qCallSetPlotView
        setPlotView(hm,hm.UserData.plot.ax(1).XLim(1));
    end
end
end

function setPlaybackSpeed(hm,hndl)
% newSpeed is fake, we detect if it went up or down and implement
% logarithmic scaling
newSpeed = round(hndl.getValue,3);  % need to round here because of +0.00001 at end to help with rounding. hacky but works, this whole function...
currentSpeed = round(hm.UserData.time.timeIncrement/hm.UserData.time.tickPeriod,3);
if newSpeed==currentSpeed
    return;
elseif newSpeed<currentSpeed
    newSpeed = 2^floor(log2(newSpeed));
else
    newSpeed = 2^ ceil(log2(newSpeed));
end

% set new playback speed
hm.UserData.time.timeIncrement = hm.UserData.time.tickPeriod*newSpeed;
% update spinner
hndl.value = newSpeed+0.00001;  % to help with rounding correctly.... apparently spinner uses bankers rounding or so
end

function setPlotView(hm,left)
% clip to time start and end
if left < 0
    left = 0;
end
if left+hm.UserData.plot.timeWindow > hm.UserData.time.endTime
    left = hm.UserData.time.endTime - hm.UserData.plot.timeWindow;
end

if left~=hm.UserData.plot.ax(1).XLim(1) || left+hm.UserData.plot.timeWindow~=hm.UserData.plot.ax(1).XLim(2)
    % changed, update data plots
    [hm.UserData.plot.ax.XLim] = deal(left+[0 hm.UserData.plot.timeWindow]);
    % update data trail
    if strcmp(hm.UserData.vid.gt.Visible,'on')
        setDataTrail(hm);
    end
    
    % update slider (we assume slider always matches axes limits. So would
    % always need to update
    hm.UserData.ui.VCR.slider.jComp.LowValue = left*hm.UserData.ui.VCR.slider.fac;
    hm.UserData.ui.VCR.slider.jComp.HighValue=(left+hm.UserData.plot.timeWindow)*hm.UserData.ui.VCR.slider.fac;
end

timeWindow = findobj(hm.UserData.ui.setting.panel.UserData.comps,'Tag','TWSpinner');
if timeWindow.Value~=hm.UserData.plot.timeWindow
    timeWindow.Value = hm.UserData.plot.timeWindow;
end
end
