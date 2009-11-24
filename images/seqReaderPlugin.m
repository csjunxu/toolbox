function varargout = seqReaderPlugin( cmd, h, varargin )
% Plugin for seqIo and videoIO to allow reading of seq files.
%
% Do not call directly, use as plugin for seqIo or videoIO instead.
% The following is a list of commands available (srp=seqReaderPlugin):
%  h = srp('open',h,fName)    % Open a seq file for reading (h ignored).
%  h = srp('close',h);        % Close seq file (output h is -1).
%  [I,ts] =srp('getframe',h)  % Get current frame (returns [] if invalid).
%  [I,ts] =srp('getframeb',h) % Get current frame with no decoding.
%  info = srp('getinfo',h)    % Return struct with info about video.
%  [I,ts] =srp('getnext',h)   % Shortcut for 'next' followed by 'getframe'.
%  out = srp('next',h)        % Go to next frame (out=0 on fail).
%  out = srp('seek',h,frame)  % Go to specified frame (out=0 on fail).
%  out = srp('step',h,delta)  % Go to current frame+delta (out=0 on fail).
%
% USAGE
%  varargout = seqReaderPlugin( cmd, h, varargin )
%
% INPUTS
%  cmd        - string indicating operation to perform
%  h          - unique identifier for open seq file
%  varargin   - additional options (vary according to cmd)
%
% OUTPUTS
%  varargout  - output (varies according to cmd)
%
% EXAMPLE
%
% See also SEQIO, SEQWRITERPLUGIN
%
% Piotr's Image&Video Toolbox      Version 2.40
% Copyright 2009 Piotr Dollar.  [pdollar-at-caltech.edu]
% Please email me if you find bugs, or have suggestions or questions!
% Licensed under the Lesser GPL [see external/lgpl.txt]

% persistent variables to keep track of all loaded .seq files
persistent h1 hs cs fids infos tNms;
if(isempty(h1)), h1=int32(now); hs=int32([]); infos={}; tNms={}; end
nIn=nargin-2; in=varargin; o2=[]; cmd=lower(cmd);

% open seq file
if(strcmp(cmd,'open'))
  chk(nIn,1,2); h=length(hs)+1; hs(h)=h1; varargout={h1}; h1=h1+1;
  [pth name]=fileparts(in{1}); if(isempty(pth)), pth='.'; end
  if(nIn==1), info=[]; else info=in{2}; end
  fName=[pth filesep name]; cs(h)=-1;
  [infos{h},fids(h),tNms{h}]=open(fName,info); return;
end

% Get the handle for this instance
[v,h]=ismember(h,hs); if(~v), error('Invalid load plugin handle'); end
c=cs(h); fid=fids(h); info=infos{h}; tNm=tNms{h};

% close seq file
if(strcmp(cmd,'close'))
  chk(nIn,0); varargout={-1}; fclose(fid); kp=[1:h-1 h+1:length(hs)];
  hs=hs(kp); cs=cs(kp); fids=fids(kp); infos=infos(kp);
  tNms=tNms(kp); if(exist(tNm,'file')), delete(tNm); end; return;
end

% perform appropriate operation
switch( cmd )
  case 'getframe',  chk(nIn,0); [o1,o2]=getFrame(c,fid,info,tNm,1);
  case 'getframeb', chk(nIn,0); [o1,o2]=getFrame(c,fid,info,tNm,0);
  case 'getinfo',   chk(nIn,0); o1=info;
  case 'getnext',   chk(nIn,0); c=c+1; [o1,o2]=getFrame(c,fid,info,tNm,1);
  case 'next',      chk(nIn,0); [c,o1]=valid(c+1,info);
  case 'seek',      chk(nIn,1); [c,o1]=valid(in{1},info);
  case 'step',      chk(nIn,1); [c,o1]=valid(c+in{1},info);
  otherwise,        error(['Unrecognized command: "' cmd '"']);
end
cs(h)=c; varargout={o1,o2};

end

function chk(nIn,nMin,nMax)
if(nargin<3), nMax=nMin; end
if(nIn>0 && nMin==0 && nMax==0), error(['"' cmd '" takes no args.']); end
if(nIn<nMin||nIn>nMax), error(['Incorrect num args for "' cmd '".']); end
end

function getImgFile( fName )
% create local copy of fName which is in a imagesci/private
fName = [fName '.' mexext]; s = filesep;
sName = [fileparts(which('imread.m')) s 'private' s fName];
tName = [fileparts(mfilename('fullpath')) s 'private' s fName];
if(~exist(tName,'file')), copyfile(sName,tName); end
end

function [info, fid, tNm] = open( fName, info )
% open video for reading, get header
assert(exist([fName '.seq'],'file')==2); fid=fopen([fName '.seq'],'r','l');
if(isempty(info)), info=readHeader(fid); else
  info.numFrames=0; fseek(fid,1024,'bof'); end
switch(info.imageFormat)
  case {100,200}, ext='raw';
  case {102,201}, ext='jpg';
  case {001,002}, ext='png';
  otherwise, error('unknown format');
end; info.ext=ext;
if(strcmp(ext,'jpg')), getImgFile( 'rjpg8c' ); end
if(strcmp(ext,'png')), getImgFile( 'png' ); end
% generate unique temporary name
[tNm tNm]=fileparts(fName); t=clock; t=mod(t(end),1);
tNm=sprintf('tmp_%s_%09i.%s',tNm,round((t+rand)/2*1e9),ext);
% compute seek info for compressed images
if(strcmp(ext,'raw')), assert(info.numFrames>0); else
  oName=[fName '-seek.mat']; n=info.numFrames; if(n==0), n=10^7; end
  if(exist(oName,'file')==2), load(oName); info.seek=seek; else %#ok<NODEF>
    disp('loading seek info...'); seek=zeros(n,1,'uint32'); seek(1)=1024;
    for i=2:n
      s=seek(i-1)+fread(fid,1,'uint32')+16; valid=fseek(fid,s,'bof')==0;
      if(valid), seek(i)=s; else n=i-1; seek=seek(1:n); break; end
    end; if(info.numFrames==0), info.numFrames=n; end
    try save(oName,'seek'); catch; end; info.seek=seek; %#ok<CTCH>
  end
end
% compute frame rate from timestamps as stored fps may be incorrect
n=min(100,info.numFrames); if(n==1), return; end; ts=zeros(1,n);
for f=1:n, ts(f)=getTimeStamp(f-1,fid,info); end
ds=ts(2:end)-ts(1:end-1); ds=ds(abs(ds-median(ds))<.005);
if(~isempty(ds)), info.fps=1/mean(ds); end
end

function [frame,v] = valid( frame, info )
v=(frame>=0 && frame<info.numFrames);
end

function [I,ts] = getFrame( frame, fid, info, tNm, decode )
% get frame image (I) and timestamp (ts) at which frame was recorded
nCh=info.imageBitDepth/8; ext=info.ext;
if(frame<0 || frame>=info.numFrames), I=[]; ts=[]; return; end
switch ext
  case 'raw'
    % read in an uncompressed image (assume imageBitDepthReal==8)
    fseek(fid,1024+frame*info.trueImageSize,'bof');
    I = fread(fid,info.imageSizeBytes,'*uint8');
    if( decode )
      % reshape appropriately for mxn or mxnx3 RGB image
      siz = [info.height info.width info.imageBitDepth/8];
      if(nCh==1), I=reshape(I,siz(2),siz(1))'; else
        I = permute(reshape(I,siz(3),siz(2),siz(1)),[3,2,1]);
      end
      if(nCh==3), t=I(:,:,3); I(:,:,3)=I(:,:,1); I(:,:,1)=t; end
    end
  case 'jpg'
    fseek(fid,info.seek(frame+1),'bof'); nBytes=fread(fid,1,'uint32');
    I = fread(fid,nBytes-4,'*uint8');
    if( decode )
      % write/read to/from temporary .jpg (not that much overhead)
      assert(I(1)==255 && I(2)==216 && I(end-1)==255 && I(end)==217); % JPG
      fw=fopen(tNm,'w'); assert(fw~=-1); fwrite(fw,I); fclose(fw);
      I=rjpg8c(tNm);
    end
  case 'png'
    fseek(fid,info.seek(frame+1),'bof'); nBytes=fread(fid,1,'uint32');
    I = fread(fid,nBytes-4,'*uint8');
    if( decode )
      % write/read to/from temporary .png (not that much overhead)
      fw=fopen(tNm,'w'); assert(fw~=-1); fwrite(fw,I); fclose(fw);
      I=png('read',tNm,[]); I=permute(I,ndims(I):-1:1);
    end
  otherwise, assert(false);
end
if(nargout==2), ts=fread(fid,1,'uint32')+fread(fid,1,'uint16')/1000; end
end

function ts = getTimeStamp( frame, fid, info )
% get timestamp (ts) at which frame was recorded
if(frame<0 || frame>=info.numFrames), ts=[]; return; end
switch info.ext
  case 'raw' % uncompressed
    fseek(fid,1024+frame*info.trueImageSize+info.imageSizeBytes,'bof');
  case {'jpg','png'} % compressed
    fseek(fid,info.seek(frame+1),'bof');
    fseek(fid,fread(fid,1,'uint32')-4,'cof');
  otherwise, assert(false);
end
ts=fread(fid,1,'uint32')+fread(fid,1,'uint16')/1000;
end

function info = readHeader( fid )
% see streampix manual for info on header
fseek(fid,0,'bof');
% first 4 bytes store OxFEED, next 24 store 'Norpix seq  '
assert(strcmp(sprintf('%X',fread(fid,1,'uint32')),'FEED'));
assert(strcmp(char(fread(fid,10,'uint16'))','Norpix seq')); %#ok<FREAD>
fseek(fid,4,'cof');
% next 8 bytes for version and header size (1024), then 512 for descr
version=fread(fid,1,'int32'); assert(fread(fid,1,'uint32')==1024);
descr=char(fread(fid,256,'uint16'))'; %#ok<FREAD>
% read in more info
tmp=fread(fid,9,'uint32'); assert(tmp(8)==0);
fps = fread(fid,1,'float64'); codec=['imageFormat' int2str2(tmp(6),3)];
% store information in info struct
info=struct( 'width',tmp(1), 'height',tmp(2), 'imageBitDepth',tmp(3), ...
  'imageBitDepthReal',tmp(4), 'imageSizeBytes',tmp(5), ...
  'imageFormat',tmp(6), 'numFrames',tmp(7), 'trueImageSize', tmp(9),...
  'fps',fps, 'seqVersion',version, 'codec',codec, 'descr',descr, ...
  'nHiddenFinalFrames',0 );
assert(info.imageBitDepthReal==8);
% seek to end of header
fseek(fid,432,'cof');
end
