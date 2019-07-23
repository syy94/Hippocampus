function [obj, varargout] = eyelink(varargin)
%@eyelink Constructor function for eyelink class
%   OBJ = eyelink(varargin)
%
%   OBJ = eyelink('auto') attempts to create a eyelink object by first
%   finding the edf file for the day (<18monthday>.edf), and then extracting 
%   the eye positions. It also has fields that store the trials and sessions in a
%   day.
%
%   OBJ = eyelink('auto', 'Calibration') attempts to create an eyelink
%   object by finding the calibration edf file (P*.edf), and then creating
%   the eyelink object 
%   %%%%%%%%%%%%%%%%%%%%%%%%%%%%
%   % Instructions on eyelink %
%   %%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%example [as, Args] = eyelink('save','redo')
%
%dependencies:

Args = struct('RedoLevels',0, 'SaveLevels',0, 'Auto',0, 'ArgsOnly',0, 'Calibration',0, ...
			'CalibFileName','*_*.edf', 'NavFileName','.edf', 'EventTypeNum',24, ...
			'ScreenX',1920, 'ScreenY',1080, 'NumMessagesToClear',7, ...
			'TriggerMessage','Trigger Version 84', 'NumTrialMessages',3, ...
			'Message1',{'1  0  0  0  0  0  0  0'}, 'Message2',{'0  0  0  0  0  1  1  0'}, ...
			'Message3',{'0  0  1  0  0  0  0  0'}, 'Message4',{'0  0  0  0  0  1  1  1'}, ...
			'SessionEyeName','sessioneye');
Args.flags = {'Auto','ArgsOnly', 'Calibration'};
% Specify which arguments should be checked when comparing saved objects
% to objects that are being asked for. Only arguments that affect the data
% saved in objects should be listed here.
Args.DataCheckArgs = {'Calibration'};

%varargin contains the arguments entered into the function. Args is the
%array in which the parameter-value pairs are stored
[Args,modvarargin] = getOptArgs(varargin,Args, ...
	'subtract',{'RedoLevels','SaveLevels'}, ...
	'shortcuts',{'redo',{'RedoLevels',1}; 'save',{'SaveLevels',1}}, ...
	'remove',{'Auto'});

% variable specific to this class. Store in Args so they can be easily
% passed to createObject and createEmptyObject
Args.classname = 'eyelink';
Args.matname = [Args.classname '.mat']; %this will get the file which stores the object, if the object was saved
Args.matvarname = 'el';

% To decide the method to create or load the object
[command,robj] = checkObjCreate('ArgsC',Args,'narginC',nargin,'firstVarargin',varargin);

if(strcmp(command,'createEmptyObjArgs'))
    varargout{1} = {'Args',Args};
    obj = createEmptyEyelink(Args);
elseif(strcmp(command,'createEmptyObj'))
    obj = createEmptyEyelink(Args);
elseif(strcmp(command,'passedObj'))
    obj = varargin{1};
elseif(strcmp(command,'loadObj'))
    % l = load(Args.matname);
    % obj = eval(['l.' Args.matvarname]);
	obj = robj;
elseif(strcmp(command,'createObj'))
    % IMPORTANT NOTICE!!!
    % If there is additional requirements for creating the object, add
    % whatever needed here
    obj = createObject(Args,modvarargin{:});
end

function obj = createObject(Args,varargin)

% move to correct directory
[pdir,cwd] = getDataOrder('Day','relative','CDNow');

if (Args.Calibration) 
	dlist = dir (Args.CalibFileName);
	if(size(dlist)>0)
		edfdata = edfmex (dlist(1).name); %get the name of the calibration edf
		fprintf ('\n');
	
		startTime = edfdata.FSAMPLE.time(1);
		type = {edfdata.FEVENT(:).type};
		type = cell2mat(type); 
		type = type - Args.EventTypeNum; %24 is the type for event messages generated by Unity 
		%messageEvent stores the message generated by Unity as the event
		%Trigger 
		messageEvent = find(~type); 
		messages = {edfdata.FEVENT(messageEvent(:)).message}'; 
	
		eventTimes = {edfdata.FEVENT(messageEvent(:)).sttime}'; %stores the time the events took place
		sz = ceil(size(eventTimes,1)/Args.NumTrialMessages); %each trial has three events in it 
		trialTimestamps = zeros (sz,Args.NumTrialMessages+1);
		idx = 1; 
	
		%This loop goes through all the messages and extracts all the
		%events in the session - start trial, start of reward, end trial or
		%failed trial.
		for i = 1:size(eventTimes,1)
		
			if(ismember(messages(i,1), Args.Message1) == 1) %start of the trial session 
				trialTimestamps (idx,1) = cell2mat(eventTimes(i,1));
			elseif(ismember(messages(i,1), Args.Message2)==1) %start of reward 
				trialTimestamps(idx,2) = cell2mat(eventTimes(i,1));
			elseif(ismember(messages(i,1), Args.Message3)==1) %end of trial session
				trialTimestamps(idx,3) = cell2mat(eventTimes(i,1));
				idx = idx+1;
			elseif(ismember(messages(i,1), Args.Message4) == 1)%failed trial
				trialTimestamps(idx,4) = cell2mat(eventTimes(i,1));
			end 
		end
		%get rid of the zeros - rows
		trialTimestamps = trialTimestamps(any(trialTimestamps,2),:);
		if (size(any(trialTimestamps(:,4)) == 0))
			trialTimestamps(:,4) = [];
		end
	
		%Use trial timestamps to index into the eye positions so as to be
		%able to draw them in the plot function
		indices = trialTimestamps-double(startTime);
		indices (indices<0) = NaN;
	
		%remove data that is outside the dimensions of the screen 
		x = (edfdata.FSAMPLE.gx(1,:))';
		x(x>Args.ScreenX)= NaN;
		%x(x<=-1)= NaN;

		y = (edfdata.FSAMPLE.gy(1,:))';
		y(y>Args.ScreenY)= NaN;
		%y(y<=-1)= NaN;

		eyePos = horzcat(x,y);
	
		%Assign values to the object data fields 
		data.trial_timestamps = trialTimestamps; 
		data.indices = indices;
		data.eyePos = eyePos;
		data.noOfSessions = 1; 

		% change directory to the eye session so the object can be saved there
		cd(Args.SessionEyeName)
		
		% create nptdata so we can inherit from it
		data.numSets = 1;    %eyelink is a session object = each session has only object 
		data.Args = Args;
		n = nptdata(data.numSets,0,pwd);
		d.data = data;
		obj = class(d,Args.classname,n);
		saveObject(obj,'ArgsC',Args);
	else  % if(size(dlist)>0)
		% create empty object
		obj = createEmptyEyelink(Args);
	end  % if(size(dlist)>0)
else  % if (Args.Calibration)  
	%create the object for the Navigation Edf file          
	%get to the day directory and create the object
	fprintf('Creating eyelink object for Navigation session\n');
	dlist = nptDir (Args.NavFileName); %look for the edf file in the session directory
	if(size(dlist)>0)
		edfdata = edfmex (dlist(1).name);%convert the edf file into a MATLAB accessible format
		fprintf ('\n');
		
		%get the number of ACTUAL sessions
		actualSessionNo = nptDir;
		actualSessionNo = {actualSessionNo.name};
		actualSessionNo = contains(actualSessionNo, {'session0'});
		actualSessionNo = size(find(actualSessionNo),2);
		%%Storing the eye positions: extract the x ad y positions of the eye
		%%and remove the eye movements where the monkey was not looking at the
		%%screen, i.e. the eye positions were outside the screen bounds
		x = (edfdata.FSAMPLE.gx(1,:))';
		x(x>Args.ScreenX)= NaN;
		%x(x<=-1)= NaN;

		y = (edfdata.FSAMPLE.gy(1,:))';
		y(y>Args.ScreenY)= NaN;
		%y(y<=-1)= NaN;

		eyePos = horzcat(x,y);

		%Extract all the messages generated by unity indicating a
		%Start/Cue/End/Timeout event in order to find all the markers and
		%their cooresponding timestamps
		type = {edfdata.FEVENT(:).type};
		type = cell2mat(type);
		type = type-Args.EventTypeNum; %the index for a 'Start/Cue/End' message is 24
		messageEvent = find (~type); %stores the indices where 'Start/Cue/End' messages were generated.
		messageEvent = messageEvent';
		m = {edfdata.FEVENT(messageEvent(:)).message}'; %this vector stores all the messages as cell chars

		%clearing the first few messages till Trigger Version # (red edf
		%file)
		mindex = 1:Args.NumMessagesToClear;
		m(mindex) = [];
		messageEvent(mindex) = [];

		%Trigger Version 84 signals the start of the session, so look for
		%all the Trigger Version 84 msgs in edf file 
		% s = {'Trigger Version 84'};
		s = Args.TriggerMessage;
		sessionIndex = find(strcmp(m, s)); %sessionIndex has the index inside messageEvent where a new session starts
		noOfSessions = size (sessionIndex, 1); %this stores the number of sessions in the day
		fprintf ('No. of Sessions %d\n',noOfSessions);
		% disp(noOfSessions);
	
		%Compares with the number of Actual Sessions found earlier 
		extraSessions = 0;
		if(noOfSessions ~= actualSessionNo) %If there are more sessions than there should be
			fprintf('Edf file has extra sessions!\n');
			extraSessions = actualSessionNo - noOfSessions;
		end

		%preallocate for speed.
		trialTimestamps = zeros(size(m,1), 3*noOfSessions); %stores timestamps at which start/cue/end trial events occured
		noOfTrials = zeros(1, 1); %stores number of trials per session
		missingData = []; %stores missing data from edf file that is then saved in an edf file
		sessionFolder = 1; %stores the current sessionFolder we are in 
	
		%This loop goes through all the sessions found in the edf file and:
		%(1)Checks if the edf file is complete by calling completeData
		%(2)fills in the trialTimestamps and missingData tables by indexing
		%   using session index (i)
		for i=1:noOfSessions 

			sessionName = dir('session*');
			if(contains(sessionName(sessionFolder).name, num2str(sessionFolder)) == 1) 
				fprintf(strcat('Session Name: ', sessionName(sessionFolder).name, '\n'));
				idx = sessionIndex(i,1); 

				if (i==noOfSessions)  
					[corrected_times,tempMissing, flag] = completeData(edfdata, m(idx:end, 1), messageEvent(idx:end,1), sessionName(sessionFolder).name, extraSessions);
				else
					idx2 = sessionIndex(i+1,1);
					[corrected_times,tempMissing, flag] = completeData(edfdata, m(idx:idx2, 1), messageEvent(idx:idx2,1), sessionName(sessionFolder).name, extraSessions);
				end

				if (flag == 0) 
					l = 1 + (sessionFolder-1)*3;
					u = 3 + (sessionFolder-1)*3;
					row = size(corrected_times,1);
					trialTimestamps (1:row, l:u) = corrected_times;
					noOfTrials (1,sessionFolder) = size(corrected_times, 1);
					missingData = vertcat(missingData, tempMissing);
					sessionFolder = sessionFolder+1;
				else 
					fprintf (strcat('Dummy Session skipped', ' ', num2str(i), '\n'));
				end 
			end 
		end

		 %edit the size of the array and remove all zero rows and extra
		 %columns 
		 trialTimestamps = trialTimestamps(any(trialTimestamps,2),:);
		 trialTimestamps=trialTimestamps(:,any(trialTimestamps));
	 
		 %modify noOf Sessions 
		 noOfSessions = size(trialTimestamps,2)/Args.NumTrialMessages;
	 
		 if(size(missingData,1) ~= 0) %if the table is not empty 
			 str = strcat('missingData_', (dlist(1).name), '.csv');
			 writetable(missingData, (str));
		 end 
	
	
		 %%Make a matrix with all the timeouts in all the trials in the session
		 %%which we can check when we are graphing lines for the end trial (refer plot.m)
		 c = {'Timeout'};
		 timeouts = contains (m,c);
		 timeouts = {edfdata.FEVENT(messageEvent(find(timeouts))).sttime}';
		 timeouts = cell2mat (timeouts); %stores all the timeouts in the session

		%Store the index of the fixation adn saccade events in the edf file
		%into the vectors indexFix and indexSacc.
		events = {edfdata.FEVENT(:).codestring}';
		indexFix = find(strcmp(events,'ENDFIX')); % get index of fixations (end fixations)
		indexSacc = find(strcmp(events,'ENDSACC')); % get index of saccades (end saccades)
		fixTimes = zeros(size(indexFix, Args.NumTrialMessages*noOfSessions));
	
		%This loop goes through all the sessions and 
		%(1)Saves the duration of fixation and saccade events for plotting
		%(2)Saves the timestamps at which fixation events occured to
		%   facilitate plotting of the raycast object (ref @raycast/plot.m)
		 for j=1:noOfSessions

			 if (j==noOfSessions)
				 idx2 = indexSacc(indexSacc > messageEvent(sessionIndex(j)));
				 idx1 = indexFix(indexFix > messageEvent(sessionIndex(j)));
			 else
				 idx2 = indexSacc(indexSacc > messageEvent(sessionIndex(j,1)) & indexSacc < messageEvent(sessionIndex(j+1,1)));
				 idx1 = indexFix(indexFix > messageEvent(sessionIndex(j,1)) & indexFix< messageEvent(sessionIndex(j+1,1))); %extract the relevant indices
			 end

			fixEvents = cell (size(idx1,1),2);
			fixEvents (:,1) =  {edfdata.FEVENT(idx1).sttime}';
			fixEvents (:,2)=  {edfdata.FEVENT(idx1).entime}';
			fixEvents = cell2mat(fixEvents);
			fixEvents(:,3)  = fixEvents(:,2) - fixEvents(:,1); %get the duration
			col = (j-1)*3+1;
			fixTimes(1:size(idx1,1),col:col+2)= fixEvents;
			fixEvents (:, 1:2) = [];
			fix(1:size(idx1,1), j) = fixEvents;

			saccEvents = cell (size(idx2,1),2);
			saccEvents (:,1) =  {edfdata.FEVENT(idx2).sttime}';
			saccEvents (:,2)=  {edfdata.FEVENT(idx2).entime}';
			saccEvents = cell2mat(saccEvents);
			saccEvents(:,3)  = saccEvents(:,2) - saccEvents(:,1); %get the duration
			saccEvents (:, 1:2) = [];
			sacc(1:size(idx2,1),j) = saccEvents;

		 end

		 %remove all the excess 0 row
		 fix = fix(any(fix,2),:);
		 sacc = sacc(any(sacc,2), :);
	
		 %This for loop splits the created matrices, which contain
		 %timestamps from all sessions, into session objects. 
		 for idx=1:noOfSessions
			 %this selects the session director and cds into it
			 strName = sessionName(idx).name;
			 cd (strName);

			 l = 1+(idx-1)*Args.NumTrialMessages;
			 u = l+2;
			 data.trial_timestamps = trialTimestamps(:, l:u); %contains all start, cue and and times for all the trials
			 data.trial_timestamps = data.trial_timestamps(any(data.trial_timestamps,2),:);

			 data.sacc_event = sacc;
			 data.fix_event = fix;
			 data.fix_times = fixTimes;
			 data.timestamps = (edfdata.FSAMPLE.time)'; %all the time that the experiments were run for
			 data.eye_pos = eyePos;  %contains all the eye positions in all the sessions
			 data.noOfSessions = noOfSessions;
			 data.timeouts = timeouts;
			 data.noOfTrials= noOfTrials(1, idx);
			 data.expTime =  edfdata.FEVENT(1).sttime; 

			 % create nptdata so we can inherit from it
			 data.numSets = 1;    %eyelink is a session object = each session has only object 
			 data.Args = Args;
			 n = nptdata(data.numSets,0,pwd);
			 d.data = data;
			 obj = class(d,Args.classname,n);
			 saveObject(obj,'ArgsC',Args);

			 %after saving object, we cd back to the parent directory 
			 cd ..
		 end  % for idx=1:noOfSessions
	else  % if(size(dlist)>0)
		% create empty object
		obj = createEmptyEyelink(Args);
	end  % if(size(dlist)>0)
end  % if (Args.Calibration) 

cd(cwd);


%---------------------------------------
%This function creates an empty object for storing eyelink info
function obj = createEmptyEyelink(Args)

% these are object specific fields
data.trial_timestamps = []; %contains all start, cue and and times for all the trials
data.sacc_event = [];
data.fix_event = [];
data.timestamps = []; %all the time that the experiments were run for
data.eye_pos = [];  %contains all the eye positions in all the sessions
%data.eyeEvent_time = eventTimestamps; %contains all the indices of all the events
data.noOfSessions = 0;
%data.exp_start_time = double(startTime);
data.timeouts = [];
data.noOfTrials= 0;


% create nptdata so we can inherit from it
% useful fields for most objects
data.numSets = 0;
data.Args = Args;
n = nptdata(0,0);
d.data = data;
obj = class(d,Args.classname,n);
