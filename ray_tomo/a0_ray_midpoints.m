% Script to do the ray theory tomography based on the ambient noise measurement
% Written by Ge Jin, jinwar@gmail.com
% Nov 2012
%
% Modified by NJA, April 2016
% Modified by JBR, 9/27/17

clear; close all;

comp = {'ZZ'};
xspdir = 'test_1.6win_avg'; %'Nomelt3inttaper_iso.s0to333_br1avg'; %'4.0_S1_10pers_avg'; %'Nomelt3inttaper_iso.s0to333_br1avg'; %'4.0_S0_waverage';

% comp = {'TT'};
% xspdir = 'Nomelt3inttaper_iso.t0to500_br0avg'; %'Nomelt3inttaper_iso_waverage'; %'4.0_S0_waverage'; %'Nomelt3inttaper_iso_T1'; %'Nomelt3inttaper_iso_waverage'; %'Nomelt3inttaper_iso'; %'4.2kmsstart';

% aniso_data = 'phv_2theta4theta_wRMS_SNRtol0_disttol200_errtol0.7.mat';
frange = [1/40 1/15]; %[1/10 1/4]; %[1/30 1/12]; %[0.1 0.25];

% QC parameters
% snr_tol = 2; %0; % 5
% r_tol_min = 0; %200; %200; % 100 km
% r_tol_max = 600;
% err_tol = 0.5; %100; %0.7; %100;

% 1-D
snr_tol = 3; %0; % 5
r_tol_min = 150; %90; %150; %200; %200; % 100 km
r_tol_max = 600;
% err_tol = 0.5; % FOR AGU17
err_tol = 0.5; %100; %0.7; %100;

windir = 'window3hr_LH_Zcorr'; %'window0.2hr'; %'window24hr_specwhite';

% r = 0.01; % Controls color bar;

%%

% Load color scale
load seiscmap.mat

% Load station info
[sta.name, sta.lat, sta.lon, sta.dep] = textread('stations_all','%s %f %f %f');

% Load anisotropy data
% load(['./aniso_DATA/',xspdir,'/',aniso_data]);

% % savefile = parameters.savefile;
% savefile = ['test'];

% figure output path
phv_fig_path = ['./figs/',windir,'/fullStack/raytomo/',num2str(1/frange(2)),'_',num2str(1/frange(1)),'s_',xspdir,'/'];
if ~exist(phv_fig_path)    
    mkdir(phv_fig_path);
end

% Set up geometry parameters
setup_parameters_tomo;
setup_parameters;
lalim = parameters.lalim;
lolim = parameters.lolim;
gridsize = parameters.gridsize;
xnode=lalim(1):gridsize:lalim(2);
ynode=lolim(1):gridsize:lolim(2);
Nx = length(xnode);
Ny = length(ynode);

% Save results?
isoutput = 1;

% Set up error parameters
% errlevel = parameters.errlevel;
% snrtol = parameters.snrtol;
% mincoherenum = parameters.mincoherenum;
fiterrtol = parameters.fiterrtol;

% refv = parameters.refv;
% distrange = parameters.distrange;

maxerrweight = parameters.maxerrweight;
polyfit_dt_err = parameters.polyfit_dt_err;
smweight0 = parameters.smweight0;


dterrtol = parameters.dterrtol;

raydensetol = parameters.raydensetol;
r = parameters.r;

xnode=lalim(1):gridsize:lalim(2);
ynode=lolim(1):gridsize:lolim(2);
[xi yi] = ndgrid(xnode,ynode);
Nx = length(xnode);
Ny = length(ynode);

% read in bad station list, if existed
if exist('badsta.lst')
    badstnms = textread('badsta.lst','%s');
    badstaids = find(ismember({stainfo.staname},badstnms));
    disp('Found Bad stations:')
    disp(badstnms)
end


% Initialize the xsp structure
% Xsp_path = './Xsp/';
Xsp_path = ['../Xsp/',windir,'/fullStack/Xsp',comp{1},'/',num2str(1/frange(2)),'_',num2str(1/frange(1)),'s_',xspdir,'/'];
xspfiles = dir([Xsp_path,'*_xsp.mat']);

disp('Looking at Xsp Files')
for ixsp = 1:length(xspfiles)
    
    temp = load([Xsp_path,xspfiles(ixsp).name]);
    xspinfo = temp.xspinfo;
    
    if ixsp ==1
        Tperiods = (2*pi)./temp.twloc;
        waxis = temp.waxis;
        twloc = temp.twloc;
        xspinfo.isgood = 0;
        xspsum = xspinfo;
    else
        xspinfo.isgood = 0;
        xspsum = [xspsum;xspinfo];
    end
    clear temp

    
    % 	xspinfo(ixsp).isgood = 0;
%     if xspsum(ixsp).sumerr < errlevel ...
%             && xspsum(ixsp).snr > snrtol && xspsum(ixsp).coherenum > mincoherenum
%         xspsum(ixsp).isgood = 1;
%     end

    if xspinfo.snr >= snr_tol && xspinfo.r >= r_tol_min && xspinfo.r <= r_tol_max && xspinfo.sumerr <= err_tol
        xspsum(ixsp).isgood = 1;
    end
    
    if rem(ixsp,500)==0
        disp(['Looking at #',num2str(ixsp),' of ',num2str(length(xspfiles))])
    end
end % end of loop ixsp'

% Loop through periods
for ip=1:length(Tperiods)
    disp(' ');
    disp(['Inversing Period: ',num2str(Tperiods(ip))]);
    clear rays dt fiterr mat phaseg err raydense dist snrs phv phv_cor
    raynum = 0;
    
    for ixsp = 1:length(xspsum)
        if xspsum(ixsp).isgood ==0;
            continue;
        end
        
        raynum = raynum+1;
        rays(raynum,1) = xspsum(ixsp).lat1;
        rays(raynum,2) = xspsum(ixsp).lon1;
        rays(raynum,3) = xspsum(ixsp).lat2;
        rays(raynum,4) = xspsum(ixsp).lon2;
        
        dist(raynum) = deg2km(distance(rays(raynum,1),rays(raynum,2),rays(raynum,3),rays(raynum,4)));
        dt(raynum) = xspsum(ixsp).tw(ip);
        snrs(raynum) = xspsum(ixsp).snr;
        
        % Midpoint of rays
        midlat(raynum) = (rays(raynum,1)+rays(raynum,3))./2;
        midlon(raynum) = (rays(raynum,2)+rays(raynum,4))./2;
        
        % Phase velocity of ray
        phv(raynum) = dist(raynum)./dt(raynum); % km/s
        
        % Azimuth of rays
        [~,azi(raynum)]=distance(xspsum(ixsp).lat1,xspsum(ixsp).lon1,xspsum(ixsp).lat2,xspsum(ixsp).lon2);
        if azi(raynum) > 180
            azi(raynum) = azi(raynum) - 360;
        end
        
        % Phase velocity corrected for azimuthal anisotropy
%         A2 = aniso.A2(ip);
%         A4 = aniso.A4(ip);
%         phi2 = aniso.phi2(ip);
%         phi4 = aniso.phi4(ip);
%         c_iso = aniso.c_iso(ip);       
%         if comp{1}(1) == 'Z'
%             phv_cor(raynum) = phv(raynum) - A2*c_iso*cosd(2*(azi(raynum) - phi2));
%         elseif comp{1}(1) == 'T'
%             phv_cor(raynum) = phv(raynum) - A2*c_iso*cosd(2*(azi(raynum)-phi2)) - A4*c_iso*cosd(4*(azi(raynum)-phi4)); 
%         end
%         
    end
    dat(ip).rays = rays;
    dat(ip).dist = dist;
    dat(ip).dt = dt; 
    dat(ip).midlat = midlat;
    dat(ip).midlon = midlon;
    dat(ip).phv = phv;
%     dat(ip).phv_cor = phv_cor;
    dat(ip).period = Tperiods(ip);
    dat(ip).snrs = snrs;
end

%%

% Load seafloor age
% load('age_grid.mat');

Mp = 3; Np = 4;

fig20 = figure(20);
set(gcf,'position',[1    1   1244   704]);
clf
rbc = flip(redbluecmap);
% rbc = rbc([1 2 3 4 5 7 8 9 10 11],:);
for ip=1:length(Tperiods)
subplot(Mp,Np,ip)
    ax = worldmap(lalim, lolim);
    set(ax, 'Visible', 'off')
    
%     avgv = nanmean(dat(ip).phv_cor);
    avgv = nanmean(dat(ip).phv);
    vels = linspace(avgv*(1-r),avgv*(1+r),size(rbc,1));
    clrs = [];
    for ixsp = 1:length(dat(ip).phv)
        lat1 = dat(ip).rays(ixsp,1);
        lon1 = dat(ip).rays(ixsp,2);
        lat2 = dat(ip).rays(ixsp,3);
        lon2 = dat(ip).rays(ixsp,4);
%         [~,iclr] = min(abs(vels - dat(ip).phv_cor(ixsp)));
        [~,iclr] = min(abs(vels - dat(ip).phv(ixsp)));
%         plotm([lat1 lat2],[lon1 lon2],dat(ip).phv(ixsp),'color',rbc(iclr,:),'linewidth',1.5);
        clrs(ixsp,:) = rbc(iclr,:);
        hold on;
    %     drawlocal
    end
    h = plotm([dat(ip).rays(:,1) dat(ip).rays(:,3)]',[dat(ip).rays(:,2) dat(ip).rays(:,4)]','linewidth',1.5);
    set(h,{'color'},num2cell(clrs,2));
    title([num2str(Tperiods(ip))],'fontsize',15)
    colorbar
%     colormap(seiscmap)
    colormap(rbc);
    caxis([vels(1) vels(end)]);
    
    plotm(sta.lat,sta.lon,'ok','markerfacecolor',[0 0 0]);
%     [c,h] = contourm(age_grid.LAT,age_grid.LON,age_grid.AGE,'k','LevelStep',5);
    drawnow;
end
save2pdf([phv_fig_path,comp{1}(1),'_','r',num2str(r_tol_min),'_',num2str(r_tol_max),'_snr',num2str(snr_tol),'_err',num2str(err_tol),'_rays.pdf'],fig20,1000);

%%
% fig21 = figure(21); % with azi correction
% set(gcf,'position',[1    1   1244   704]);
% clf
% 
% 
% for ip=1:length(Tperiods)
%     subplot(Mp,Np,ip)
%     ax = worldmap(lalim, lolim);
%     set(ax, 'Visible', 'off')
% %     surfacem(xi,yi,raytomo(ip).err);
% %     drawpng
% % scatterm(dat(ip).midlat,dat(ip).midlon,30,dat(ip).phv,'filled'); 
% % scatterm(dat(ip).midlat,dat(ip).midlon,60,dat(ip).phv_cor,'filled'); 
% scatterm(dat(ip).midlat,dat(ip).midlon,60,dat(ip).phv,'filled');
% % plotm(sta.lat,sta.lon,'ok','markerfacecolor',[0 0 0]);
% 
% hold on;
% % drawlocal
% title([num2str(Tperiods(ip))],'fontsize',15)
% 
% % avgv = nanmean(dat(ip).phv_cor);
% avgv = nanmean(dat(ip).phv);
% caxis([avgv*(1-r) avgv*(1+r)])
% colorbar
% % colormap(seiscmap)
% % colormap(flip(jet))
% rbc = flip(redbluecmap);
% % rbc = rbc([1 2 3 4 5 7 8 9 10 11],:);
% colormap(rbc);
% 
% [c,h] = contourm(age_grid.LAT,age_grid.LON,age_grid.AGE,'k','LevelStep',5);
% end
%%

fig22 = figure(22); % without azi corr
set(gcf,'position',[1    1   1244   704]);
clf
for ip=1:length(Tperiods)
    subplot(Mp,Np,ip)
    ax = worldmap(lalim, lolim);
    set(ax, 'Visible', 'off')
%     surfacem(xi,yi,raytomo(ip).err);
%     drawpng
% scatterm(dat(ip).midlat,dat(ip).midlon,30,dat(ip).phv,'filled'); 
scatterm(dat(ip).midlat,dat(ip).midlon,60,dat(ip).phv,'filled'); 
% plotm(sta.lat,sta.lon,'ok','markerfacecolor',[0 0 0]);

hold on;
% drawlocal
title([num2str(Tperiods(ip))],'fontsize',15)

% avgv = nanmean(dat(ip).phv_cor);
avgv = nanmean(dat(ip).phv);
caxis([avgv*(1-r) avgv*(1+r)])
colorbar
% colormap(seiscmap)
% colormap(flip(jet))
rbc = flip(redbluecmap);
% rbc = rbc([1 2 3 4 5 7 8 9 10 11],:);
colormap(rbc);

[c,h] = contourm(age_grid.LAT,age_grid.LON,age_grid.AGE,'k','LevelStep',5);
end

% save2pdf([phv_fig_path,comp{1}(1),'_','r',num2str(r_tol_min),'_',num2str(r_tol_max),'_snr',num2str(snr_tol),'_err',num2str(err_tol),'_ray_midpts_azicorr.pdf'],fig21,1000);
save2pdf([phv_fig_path,comp{1}(1),'_','r',num2str(r_tol_min),'_',num2str(r_tol_max),'_snr',num2str(snr_tol),'_err',num2str(err_tol),'_ray_midpts.pdf'],fig22,1000);