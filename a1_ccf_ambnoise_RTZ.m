% Calculate ambient noise cross correlation record from multiple stationpairs 
% for (Z, R, T) using the methods from Bensen et al. (2007) GJI 
% DOI:10.1111/j.1365-246X.2007.03374.x
% !! Currently requires data to be downsampled to 1 Hz !!
%
% Expects files organized like so:
% {datadirectory}/{station}/{station}.{yyyy}.{jday}.{hh}.{mm}.{SS}.{COMP}.sac
%  e.g.: mydata/CC05/CC05.2018.112.00.00.00.BDH.sac
%
%   (NOTE: FUNCTIONIZE IN THE FUTURE)
% Patty Lin -- 10/2014
% Natalie Accardo
% Josh Russell
% https://github.com/jbrussell
clear;
setup_parameters;

IsFigure1 = 1;
IsFigure2 = 0;
IsOutputFullstack = 1; % Save full year ccf stacks
IsOutputMonthstack = 0; % save month ccf stacks
IsOutputDaystack = 0; % save day ccf stacks
IsOutputSinglestack = 0; % save single ccf before stacking
IsOutputSeismograms = 0; % save raw seismograms before cross-correlating

IsRemoveIR = 0; % remove instrument response
IsDetrend = 1; % detrend the data
IsSpecWhiten = 1; % Whiten spectrum
IsTaper = 1; % Apply cosine taper to data chunks

% input path
datadir = parameters.datapath;
PZpath = parameters.PZpath;
figpath = parameters.figpath;
seis_path = parameters.seis_path;
orientation_path = parameters.orientation_path;
dt = parameters.dt;
winlength = parameters.winlength;

year = ''; %'2012';
Nstart = 50; % (seconds) offset start of file
Nstart = Nstart/dt;
npts= 86000; % (seconds) Length of full dayfiles
npts = npts/dt;
comp = parameters.comp;

%dist_min = 20;
dist_min = parameters.mindist;

% Build File Structure: cross-correlations
ccf_path = './ccf/';
ccf_winlength_path = [ccf_path,'window',num2str(winlength),'hr/'];
ccf_singlestack_path = [ccf_winlength_path,'single/'];
ccf_daystack_path = [ccf_winlength_path,'dayStack/'];
ccf_monthstack_path = [ccf_winlength_path,'monthStack/'];
ccf_fullstack_path = [ccf_winlength_path,'fullStack/'];

if ~exist(ccf_path)
    mkdir(ccf_path)
end
if ~exist(ccf_winlength_path)
    mkdir(ccf_winlength_path)
end
if ~exist(ccf_singlestack_path)
    mkdir(ccf_singlestack_path)
end
if ~exist(ccf_daystack_path)
    mkdir(ccf_daystack_path)
end
if ~exist(ccf_monthstack_path)
    mkdir(ccf_monthstack_path)
end
if ~exist(ccf_fullstack_path)
    mkdir(ccf_fullstack_path)
end

PATHS = {ccf_singlestack_path; ccf_daystack_path; ccf_monthstack_path; ccf_fullstack_path};
for ipath = 1:length(PATHS)
    ccfR_path = [PATHS{ipath},'ccfRR/'];
    ccfT_path = [PATHS{ipath},'ccfTT/'];
    ccfZ_path = [PATHS{ipath},'ccfZZ/'];
    if ~exist(ccfR_path)
        mkdir(ccfR_path);
    end
    if ~exist(ccfT_path)
        mkdir(ccfT_path);
    end
    if ~exist(ccfZ_path)
        mkdir(ccfZ_path);
    end
end

% Build File Structure: figures
fig_winlength_path = [figpath,'window',num2str(winlength),'hr/'];
if ~exist(figpath)
    mkdir(figpath);
end
if ~exist(fig_winlength_path)
    mkdir(fig_winlength_path)
end

% Build File Structure: windowed seismograms
seis_winlength_path = [seis_path,'window',num2str(winlength),'hr/'];
if ~exist(seis_path)
    mkdir(seis_path);
end
if ~exist(seis_winlength_path)
    mkdir(seis_winlength_path)
end


%% ------------------- loop through center station station-------------------

stalist = parameters.stalist;
nsta=parameters.nsta; % number of target stations to calculate for

% READ OBS ORIENTATIONS
[slist, orientations] = textread(orientation_path,'%s%f\n');

for ista1=1:nsta

    sta1=char(stalist(ista1,:));
    % Build station directories
    for ipath = 1:length(PATHS)
        ccfR_path = [PATHS{ipath},'ccfRR/'];
        ccfT_path = [PATHS{ipath},'ccfTT/'];
        ccfZ_path = [PATHS{ipath},'ccfZZ/'];
        if ~exist([ccfR_path,sta1])
            mkdir([ccfR_path,sta1]);
        end
        if ~exist([ccfT_path,sta1])
            mkdir([ccfT_path,sta1]);
        end
        if ~exist([ccfZ_path,sta1])
            mkdir([ccfZ_path,sta1]);
        end
    end
    seisT_path = [seis_winlength_path,'T/'];
    seisR_path = [seis_winlength_path,'R/'];
    seisZ_path = [seis_winlength_path,'Z/'];
    seisH1_path = [seis_winlength_path,'H1/'];
    seisH2_path = [seis_winlength_path,'H2/'];
    if ~exist([seisT_path,sta1])
        mkdir([seisT_path,sta1]);
    end
    if ~exist([seisR_path,sta1])
        mkdir([seisR_path,sta1]);
    end
    if ~exist([seisZ_path,sta1])
        mkdir([seisZ_path,sta1]);
    end
    if ~exist([seisH1_path,sta1])
        mkdir([seisH1_path,sta1]);
    end
    if ~exist([seisH2_path,sta1])
        mkdir([seisH2_path,sta1]);
    end

    list1 = dir([datadir,sta1,'/*Z.sac']);

    for ista2=1:nsta
        clear lat1 lat2 lon1 lon2 dist az baz vec_tz2 Z2raw vec_tz Z1raw

        sta2=char(stalist(ista2,:));

        % if same station, skip
        if(strcmp(sta1,sta2))
            continue
        end


        % check to see if we've already done this ccf
        if(exist([ccfR_path,sta1,'/',sta1,'_',sta2,'_f.mat']))
            display('CCF already exist, skip this pair');
            continue
        elseif exist([ccfT_path,sta1,'/',sta2,'_',sta1,'_f.mat'])
            display('CCF already exist, skip this pair');
            continue
        elseif exist([ccfZ_path,sta1,'/',sta2,'_',sta1,'_f.mat'])
            display('CCF already exist, skip this pair');
            continue
        end

        display(['performing cross-correlation for staion pair : ',sta1,'  ', sta2]);
        % -------------loop through each half day--------------------
        nday_stack=0;
        coh_sumR = 0;
        coh_sumT = 0;
        coh_sumZ = 0;
        coh_num = 0;

        % Get a list of all available data
        ihday = 0;
        month_counter = 0;
        imonth = 0;
        for ifil = 1:length(list1)
            file1cZ = list1(ifil).name;
            file1cH1 = strrep(file1cZ,[comp,'Z'],[comp,'1']);
            file1cH2 = strrep(file1cZ,[comp,'Z'],[comp,'2']);

            % Check that day file exists for station 2
            file2cZ = dir([datadir,sta2,'/',sta2,file1cZ(5:end)]);
            file2cH1 = dir([datadir,sta2,'/',sta2,file1cH1(5:end)]);
            file2cH2 = dir([datadir,sta2,'/',sta2,file1cH2(5:end)]);
            hdayid = file1cZ(6:22);
            if isempty(file2cZ) || isempty(file2cH1) || isempty(file2cH2)
                disp(['No data for ',sta2,' on day ',hdayid,'... skipping'])
                continue
            end
            file2cZ = file2cZ.name;
            file2cH1 = file2cH1.name;
            file2cH2 = file2cH2.name;

            if month_counter == 0
                coh_sumR_month = 0;
                coh_sumT_month = 0;
                coh_sumZ_month = 0;
                coh_num_month = 0;
            end
            clear data1cH1 data1cH2 data1cZ data2cH1 data2cH2 data2cZ
            ihday = ihday +1;
            month_counter = month_counter + 1;
            clear temp
            %temp = strsplit(daylist1(ihday).name,'.');

            disp(['Looking at ',hdayid,' ',sta2]);

            data1cH1=dir([datadir,sta1,'/',year,'/',sta1,'.',hdayid,'.*1.sac']);
            data1cH2=dir([datadir,sta1,'/',year,'/',sta1,'.',hdayid,'.*2.sac']);
            data1cZ= dir([datadir,sta1,'/',year,'/',sta1,'.',hdayid,'.*Z.sac']);
            data2cH1=dir([datadir,sta2,'/',year,'/',sta2,'.',hdayid,'.*1.sac']);
            data2cH2=dir([datadir,sta2,'/',year,'/',sta2,'.',hdayid,'.*2.sac']);
            data2cZ= dir([datadir,sta2,'/',year,'/',sta2,'.',hdayid,'.*Z.sac']);

            data1cH1 = [datadir,sta1,'/',year,'/',data1cH1.name];
            data1cH2 = [datadir,sta1,'/',year,'/',data1cH2.name];
            data1cZ =  [datadir,sta1,'/',year,'/',data1cZ.name];
            data2cH1 = [datadir,sta2,'/',year,'/',data2cH1.name];
            data2cH2 = [datadir,sta2,'/',year,'/',data2cH2.name];
            data2cZ =  [datadir,sta2,'/',year,'/',data2cZ.name];

            %------------------- TEST IF DATA EXIST------------------------
            [S1H1t,S1H1raw]=readsac(data1cH1);
            [S1H2t,S1H2raw]=readsac(data1cH2);
            [S1Zt,S1Zraw]=readsac(data1cZ);
            [S2H1t,S2H1raw]=readsac(data2cH1);
            [S2H2t,S2H2raw]=readsac(data2cH2);
            [S2Zt,S2Zraw]=readsac(data2cZ);

            %------------------- Remove instrument response ------------------------
        if IsRemoveIR
            pzfile1 = dir([PZpath,'SAC_PZs_*',sta1,'_*H1_*']); % PZ for H1 and H2 are identical
            pzfile2 = dir([PZpath,'SAC_PZs_*',sta2,'_*H1_*']);

            % do lazy checks to make sure only one PZ file is found for each station
            if length(pzfile1) ~= 1
                pzfile = pzfile1;

                % Figure out which response to read
                for ii = 1:length(pzfile)
                    pzdate(ii) = doy2date(str2num(pzfile(ii).name(19:21)),str2num(pzfile(ii).name(14:17)));
                end
                otime = datenum(hdayid,'yyyymmddHHMMSS');
                ind = find(abs(otime-pzdate) == min(abs(otime-pzdate)));
                if ind > length(pzfile) & ind > 1
                    ind = ind(end)-1;
                end
                pzfile = pzfile(ind);
                pzfile1 = pzfile;

            elseif length(pzfile2) ~= 1
                pzfile = pzfile2;

                % Figure out which response to read
                for ii = 1:length(pzfile)
                    pzdate(ii) = doy2date(str2num(pzfile(ii).name(19:21)),str2num(pzfile(ii).name(14:17)));
                end
                otime = datenum(hdayid,'yyyymmddHHMMSS');
                ind = find(abs(otime-pzdate) == min(abs(otime-pzdate)));
                if ind > length(pzfile) & ind > 1
                    ind = ind(end)-1;
                end
                pzfile = pzfile(ind);
                pzfile2 = pzfile;
            end
            dt_new = parameters.dt;

        % Read sacpz file for station 1
        [p,z,c] = read_SACPZ([PZpath,pzfile1.name]);

        dt1 = abs(S1H1t(1)-S1H1t(2));
        dt2 = abs(S2H1t(1)-S2H1t(2));

        % Remove instrument response for station 1 H1 & H2
        S1H1raw = rm_SACPZ(S1H1raw,z,p,c,dt1);
        S1H2raw = rm_SACPZ(S1H2raw,z,p,c,dt1);
        S1Zraw = rm_SACPZ(S1Zraw,z,p,c,dt1);

        % Read sacpz file for station 2
        [p,z,c] = read_SACPZ([PZpath,pzfile2.name]);

        % Remove instrument response for station 2 H1 & H2
        S2H1raw = rm_SACPZ(S2H1raw,z,p,c,dt2);
        S2H2raw = rm_SACPZ(S2H2raw,z,p,c,dt2);
        S2Zraw = rm_SACPZ(S2Zraw,z,p,c,dt2);
        end


        % Check to make sure there's actual data
        zeroind1 = find(S1H1raw == 0);
        zeroind2 = find(S2H1raw == 0);
        if length(zeroind1) == length(S1H1raw) || length(zeroind2) == length(S2H1raw)
            disp('All zeros!');
            continue
        end

        if(length(S1H1t)*length(S1H2t)*length(S1Zt)*length(S2H1t)*length(S2H2t)*length(S2Zt)==0)
            display(['no data for ! station ',sta2]);
            continue
        end

        % Determine the time span to cut to ... this will change with
        % different segments
        clear tcut
        minT1H1 = min(S1H1t);
        minT2H1 = min(S2H1t);
        minT1H2 = min(S1H2t);
        minT2H2 = min(S2H2t);
        minT1Z = min(S1Zt);
        minT2Z = min(S2Zt);

        if length(S1H1raw) < 30000 || length(S1H2raw) < 30000
            disp(['Sta1 ',sta1,' : ',num2str(length(S1H2raw)),' is too short!'])
            continue
        elseif length(S2H1raw) < 30000 || length(S2H2raw) < 30000
            disp(['Sta2 ',sta2,' : ',num2str(length(S2H2raw)),' is too short!'])
            continue
        end


            if(~exist('lat2','var'));

                S1 = readsac(data1cH1);
                S2 = readsac(data2cH1);

                lat1=S1.STLA;
                lon1=S1.STLO;
                dep1=S1.STEL; % depth is negative for OBS and positive for land stations


                lat2=S2.STLA;
                lon2=S2.STLO;
                dep2=S2.STEL; % depth is negative for OBS and positive for land stations


                % Get the interstation distance and azimuth
                [delta,S1az]=distance(lat1,lon1,lat2,lon2);
                [delta,S2az]=distance(lat2,lon2,lat1,lon1);

                dist=deg2km(delta);

                Delta=S1.DELTA;
                if(abs(Delta-dt) >= 0.01*dt )
                    error('sampling interval does not match data! check dt');
                end

                if(dist < dist_min)
                    display('distance shorter than 80 km, skip');
                    break
                end
            end % if lat variabls

            stapairsinfo.stanames = {sta1,sta2};
            stapairsinfo.lats = [lat1,lat2];
            stapairsinfo.lons = [lon1,lon2];

            % START WINDOWING
            hour_length = winlength;

            nwin = floor(24/hour_length)*2-1; %
            win_length = hour_length*60*60*dt; % length of individual windows.
            win_start = 1;
            coh_sumT_day = 0;
            coh_sumR_day = 0;
            coh_sumZ_day = 0;
            coh_num_day = 0;
            last_pt = win_length*.5*(nwin-1)+1+Nstart*dt+win_length;
            if last_pt < length(S1H1raw)
                nwin = nwin + 1;
            end
			for iwin = 1:nwin
				clear tcut S1R S2R S1T S2T S1Z S2Z fftS1R fftS2R fftS1T fftS2T fftS1Z fftS2Z

				% cut in time
                if hour_length == 24
                    pts_begin = Nstart*dt;
                    pts_end = length(S1H1raw)-Nstart*dt;
                else
                    pts_begin = win_length*.5*(iwin-1)+1+Nstart*dt;
                    pts_end = pts_begin+win_length;
                end

                if pts_begin > length(S1H1raw) || pts_begin > length(S2H1raw) || pts_end > length(S1H1raw) || pts_end > length(S2H1raw)
					disp('(H1) Points greater than the data... fixing window');
                    pts_begin = length(S1H1raw)-win_length-Nstart*dt;
                    pts_end = pts_begin+win_length;
					%continue
                elseif pts_begin > length(S1H2raw) || pts_begin > length(S2H2raw) || pts_end > length(S1H2raw) || pts_end > length(S2H2raw)
					disp('(H2) Points greater than the data... fixing window');
					pts_begin = length(S1H2raw)-win_length-Nstart*dt;
                    pts_end = pts_begin+win_length;
                    %continue
                elseif pts_begin > length(S1Zraw) || pts_begin > length(S2Zraw) || pts_end > length(S1Zraw) || pts_end > length(S2Zraw)
					disp('(Z) Points greater than the data... fixing window');
					pts_begin = length(S1Zraw)-win_length-Nstart*dt;
                    pts_end = pts_begin+win_length;
                    %continue
                end
                tcut = [pts_begin:dt:pts_end];

                % cut in tim H1 H2 for STA1
                S1H1=interp1(S1H1t,S1H1raw,tcut);
                S1H1(isnan(S1H1))=0;
                S1H2=interp1(S1H2t,S1H2raw,tcut);
                S1H2(isnan(S1H2))=0;
                S1Z=interp1(S1Zt,S1Zraw,tcut);
                S1Z(isnan(S1Z))=0;

                % cut in tim H1 H2 for STA2
                S2H1=interp1(S2H1t,S2H1raw,tcut);
                S2H1(isnan(S2H1))=0;
                S2H2=interp1(S2H2t,S2H2raw,tcut);
                S2H2(isnan(S2H2))=0;
                S2Z=interp1(S2Zt,S2Zraw,tcut);
                S2Z(isnan(S2Z))=0;

                %detrend
            if IsDetrend
                S1H1 = detrend(S1H1);
                S1H2 = detrend(S1H2);
                S1Z = detrend(S1Z);
                S2H1 = detrend(S2H1);
                S2H2 = detrend(S2H2);
                S2Z = detrend(S2Z);
            end

            % Apply cosine taper
            if IsTaper
                S1H1 = cos_taper(S1H1);
                S1H2 = cos_taper(S1H2);
                S1Z = cos_taper(S1Z);
                S2H1 = cos_taper(S2H1);
                S2H2 = cos_taper(S2H2);
                S2Z = cos_taper(S2Z);
            end

                % ROTATE FROM H1-H2 TO R-T
                Ista = strcmp(sta1,slist);
                S1phi = orientations(Ista); % angle between H1 and N (CW from north)
                Ista = strcmp(sta2,slist);
                S2phi = orientations(Ista); % angle between H1 and N (CW from north)
                [S1R,S1T] = rotate_vector(S1H1,S1H2,S1az-S1phi);
                [S2R,S2T] = rotate_vector(S2H1,S2H2,S2az-S2phi+180);

                if IsFigure2
                    figure(49)
                    clf

                    %Z
                    subplot(5,1,1)
                    plot(tcut,S1Z,'-k')
                    %ylim([-0.15e-5 0.15e-5])
                    xlim([tcut(1) tcut(end)])
                    title('Z');
                    hold on

                    %H1
                    subplot(5,1,2)
                    plot(tcut,S1H1,'-k')
                    %ylim([-0.15e-5 0.15e-5])
                    xlim([tcut(1) tcut(end)])
                    title('H1');
                    hold on

                    %H2
                    subplot(5,1,3)
                    plot(tcut,S1H2,'-k')
                    %ylim([-0.15e-5 0.15e-5])
                    xlim([tcut(1) tcut(end)])
                    title('H2');
                    hold on

                    %R
                    subplot(5,1,4)
                    plot(tcut,S1R,'-k')
                    %ylim([-0.15e-5 0.15e-5])
                    xlim([tcut(1) tcut(end)])
                    title('R');
                    hold on

                    %T
                    subplot(5,1,5)
                    plot(tcut,S1T,'-k')
                    %ylim([-0.15e-5 0.15e-5])
                    xlim([tcut(1) tcut(end)])
                    title('T');
                    hold on

                    pause;
                    %return
                end


                %---------------- Transverse Component --------------
                S1T = runwin_norm(S1T);
                S2T = runwin_norm(S2T);
                
                %fft
                fftS1T = fft(S1T);
                fftS2T = fft(S2T);

                %Whiten
                if IsSpecWhiten
                    fftS1T = spectrumwhiten(fftS1T,0.001);
                    fftS2T = spectrumwhiten(fftS2T,0.001);
                end

                % calcaulate daily CCF and stack for transverse
                coh_trace = fftS1T .* conj(fftS2T);
                coh_trace = coh_trace ./ abs(fftS1T) ./ abs(fftS2T);
                coh_trace(isnan(coh_trace)) = 0;
                coh_sumT = coh_sumT + coh_trace;
                coh_trace_T = coh_trace;
                coh_sumT_day = coh_sumT_day + coh_trace;
                coh_sumT_month = coh_sumT_month + coh_trace;

                nanind = find(isnan(coh_trace));

                if length(nanind) == length(coh_trace)
                    disp('All nan!');
%                     return
                    continue
                end


                %-------------------- Radial Component --------------
                % despike
                S1R = runwin_norm(S1R);
                S2R = runwin_norm(S2R);

                %fft
                fftS1R = fft(S1R);
                fftS2R = fft(S2R);

                %Whiten
                if IsSpecWhiten
                    fftS1R = spectrumwhiten(fftS1R,0.001);
                    fftS2R = spectrumwhiten(fftS2R,0.001);
                end

                % calcaulate daily CCF and stack for radial
                coh_trace = fftS1R .* conj(fftS2R);
                coh_trace = coh_trace ./ abs(fftS1R) ./ abs(fftS2R);
                coh_trace(isnan(coh_trace)) = 0;
                coh_sumR = coh_sumR + coh_trace;
                coh_trace_R = coh_trace;
                coh_sumR_day = coh_sumR_day + coh_trace;
                coh_sumR_month = coh_sumR_month + coh_trace;

                %-------------------- Vertical Component --------------
                % despike
                S1Z = runwin_norm(S1Z);
                S2Z = runwin_norm(S2Z);

                %fft
                fftS1Z = fft(S1Z);
                fftS2Z = fft(S2Z);

                %Whiten
                if IsSpecWhiten
                    fftS1Z = spectrumwhiten(fftS1Z,0.001);
                    fftS2Z = spectrumwhiten(fftS2Z,0.001);
                end

                % calcaulate daily CCF and stack for radial
                coh_trace = fftS1Z .* conj(fftS2Z);
                coh_trace = coh_trace ./ abs(fftS1Z) ./ abs(fftS2Z);
                coh_trace(isnan(coh_trace)) = 0;
                coh_sumZ = coh_sumZ + coh_trace;
                coh_trace_Z = coh_trace;
                coh_sumZ_day = coh_sumZ_day + coh_trace;
                coh_sumZ_month = coh_sumZ_month + coh_trace;

                coh_num = coh_num + 1;
                coh_num_day = coh_num_day + 1;
                coh_num_month = coh_num_month + 1;
    %             toc

                if IsOutputSinglestack % save individual xcor
                    ccfT_singlestack_path = [ccf_singlestack_path,'ccfTT/'];
                    ccfR_singlestack_path = [ccf_singlestack_path,'ccfRR/'];
                    ccfZ_singlestack_path = [ccf_singlestack_path,'ccfZZ/'];
                    save(sprintf('%s%s/%s_%s_%d_f.mat',ccfT_singlestack_path,sta1,sta1,sta2,coh_num),'coh_trace_T','stapairsinfo');
                    save(sprintf('%s%s/%s_%s_%d_f.mat',ccfR_singlestack_path,sta1,sta1,sta2,coh_num),'coh_trace_R','stapairsinfo');
                    save(sprintf('%s%s/%s_%s_%d_f.mat',ccfZ_singlestack_path,sta1,sta1,sta2,coh_num),'coh_trace_Z','stapairsinfo');
                end
                if IsOutputSeismograms % save seismograms before xcor
                    seisT_path = [seis_winlength_path,'T/'];
                    seisR_path = [seis_winlength_path,'R/'];
                    seisZ_path = [seis_winlength_path,'Z/'];
                    seisH1_path = [seis_winlength_path,'H1/'];
                    seisH2_path = [seis_winlength_path,'H2/'];
                    save(sprintf('%s%s/%s_%d_f.mat',seisT_path,sta1,sta1,coh_num),'S1T','stapairsinfo');
                    save(sprintf('%s%s/%s_%d_f.mat',seisR_path,sta1,sta1,coh_num),'S1R','stapairsinfo');
                    save(sprintf('%s%s/%s_%d_f.mat',seisZ_path,sta1,sta1,coh_num),'S1Z','stapairsinfo');
                    save(sprintf('%s%s/%s_%d_f.mat',seisH1_path,sta1,sta1,coh_num),'S1H1','stapairsinfo');
                    save(sprintf('%s%s/%s_%d_f.mat',seisH2_path,sta1,sta1,coh_num),'S1H2','stapairsinfo');
                end
            end % end window
            if IsOutputDaystack
                % Save day stack
                ccfT_daystack_path = [ccf_daystack_path,'ccfTT/'];
                ccfR_daystack_path = [ccf_daystack_path,'ccfRR/'];
                ccfZ_daystack_path = [ccf_daystack_path,'ccfZZ/'];
                clear coh_sum
                coh_sum = coh_sumT_day;
                save(sprintf('%s%s/%s_%s_day%d_f.mat',ccfT_daystack_path,sta1,sta1,sta2,ihday),'coh_sum','coh_num_day','stapairsinfo');
                clear coh_sum
                coh_sum = coh_sumR_day;
                save(sprintf('%s%s/%s_%s_day%d_f.mat',ccfR_daystack_path,sta1,sta1,sta2,ihday),'coh_sum','coh_num_day','stapairsinfo');
                clear coh_sum
                coh_sum = coh_sumZ_day;
                save(sprintf('%s%s/%s_%s_day%d_f.mat',ccfZ_daystack_path,sta1,sta1,sta2,ihday),'coh_sum','coh_num_day','stapairsinfo');
            end
            if IsOutputMonthstack
                % Save 30 day (month) stack
                if month_counter == 30
                    imonth = imonth + 1;
                    ccfT_monthstack_path = [ccf_monthstack_path,'ccfTT/'];
                    ccfR_monthstack_path = [ccf_monthstack_path,'ccfRR/'];
                    ccfZ_monthstack_path = [ccf_monthstack_path,'ccfZZ/'];
                    clear coh_sum
                    coh_sum = coh_sumT_month;
                    save(sprintf('%s%s/%s_%s_month%d_f.mat',ccfT_monthstack_path,sta1,sta1,sta2,imonth),'coh_sum','coh_num_month','stapairsinfo');
                    clear coh_sum
                    coh_sum = coh_sumR_month;
                    save(sprintf('%s%s/%s_%s_month%d_f.mat',ccfR_monthstack_path,sta1,sta1,sta2,imonth),'coh_sum','coh_num_month','stapairsinfo');
                    clear coh_sum
                    coh_sum = coh_sumZ_month;
                    save(sprintf('%s%s/%s_%s_month%d_f.mat',ccfZ_monthstack_path,sta1,sta1,sta2,imonth),'coh_sum','coh_num_month','stapairsinfo');
                    month_counter = 0; % start over
                end
            end
        end % end hday

        if coh_num > 1
            if IsFigure1
                f101 = figure(101);clf;
%                 set(gcf,'position',[400 400 600 300]);
                subplot(3,1,1)
                dt = 1;
                T = length(coh_sumR);
                faxis = [0:1/T:1/dt/2,-1/dt/2+1/T:1/T:-1/T];
                ind = find(faxis>0);
                plot(faxis(ind),smooth(real(coh_sumR(ind)/coh_num),100));
                title(sprintf('%s %s coherency R ,station distance: %f km',sta1,sta2,dist));
                xlim([0.01 0.5])
                %xlim([0.04 0.16])
                xlabel('Frequency')

                subplot(3,1,2)
                dt = 1;
                T = length(coh_sumT);
                faxis = [0:1/T:1/dt/2,-1/dt/2+1/T:1/T:-1/T];
                ind = find(faxis>0);
                plot(faxis(ind),smooth(real(coh_sumT(ind)/coh_num),100));
                title(sprintf('%s %s coherency T ,station distance: %f km',sta1,sta2,dist));
                xlim([0.01 0.5])
                %xlim([0.04 0.16])
                xlabel('Frequency')

                subplot(3,1,3)
                dt = 1;
                T = length(coh_sumZ);
                faxis = [0:1/T:1/dt/2,-1/dt/2+1/T:1/T:-1/T];
                ind = find(faxis>0);
                plot(faxis(ind),smooth(real(coh_sumZ(ind)/coh_num),100));
                title(sprintf('%s %s coherency Z ,station distance: %f km',sta1,sta2,dist));
                xlim([0.01 0.5])
                %xlim([0.04 0.16])
                xlabel('Frequency')
                drawnow

                print(f101,'-dpsc',[fig_winlength_path,sta1,'_',sta2,'.ps']);
                %pause;
            end
            if IsOutputFullstack
                ccfT_fullstack_path = [ccf_fullstack_path,'ccfTT/'];
                ccfR_fullstack_path = [ccf_fullstack_path,'ccfRR/'];
                ccfZ_fullstack_path = [ccf_fullstack_path,'ccfZZ/'];
                clear coh_sum
                coh_sum = coh_sumT;
                save(sprintf('%s%s/%s_%s_f.mat',ccfT_fullstack_path,sta1,sta1,sta2),'coh_sum','coh_num','stapairsinfo');
                clear coh_sum
                coh_sum = coh_sumR;
                save(sprintf('%s%s/%s_%s_f.mat',ccfR_fullstack_path,sta1,sta1,sta2),'coh_sum','coh_num','stapairsinfo');
                clear coh_sum
                coh_sum = coh_sumZ;
                save(sprintf('%s%s/%s_%s_f.mat',ccfZ_fullstack_path,sta1,sta1,sta2),'coh_sum','coh_num','stapairsinfo');
            end
        end
    end % ista2

end % ista1
