function [hPatch,api] = imRectRot( varargin )

% default arguments / globals
dfs={'hParent',gca,'pos',[],'lims',[],'lineProp',{},'showLims',0};
[hParent,pos,lims,lineProp,showLims]=getPrmDflt(varargin,dfs,1);
if(length(lims)==4), lims=[lims 0]; end
[posChnCb,posSetCb]=deal([]); posLock=false; sizLock=false;

% get figure and axes handles, optionally show limits
hAx = ancestor(hParent,'axes'); assert(~isempty(hAx));
hFig = ancestor(hAx,'figure'); assert(~isempty(hFig));
set( hFig, 'CurrentAxes', hAx );
if( showLims ), [disc,xs,ys]=rectToCorners(lims);
  for j=1:4, ids=mod([j-1 j],4)+1; line(xs(ids),ys(ids)); end
end

% create patch object as well as boundaries objects
if(isempty(pos)); vis='off'; else vis='on'; end
hPatch = patch('FaceColor','none','EdgeColor','none'); hBnds=[0 0 0 0];
for j=1:4, hBnds(j)=line(lineProp{:},'Visible',vis); end
set([hBnds hPatch],'ButtonDownFcn',{@btnDwn,0},'DeleteFcn',@deleteFcn);

% set initial position
if(length(pos)==5), setPos(pos); else
  btnDwn([],[],-1); waitfor(hFig,'WindowButtonUpFcn','');
end

% create api
api = struct('getPos',@getPos, 'setPos',@setPos, ...
  'setPosChnCb',@setPosChnCb, 'setPosSetCb',@setPosSetCb, ...
  'setPosLock',@setPosLock, 'setSizLock',@setSizLock, ...
  'setAr',@setAr, 'uistack',@uistack1 );

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

  function [pc,rs,R] = rectInfo( pos0 )
    % return rectangle center, radii, and rotation matrix
    t=pos0(5); c=cosd(t); s=sind(t); R=[c -s; s c];
    rs=pos0(3:4)/2; pc=pos0(1:2)+rs;
  end

  function [pts,xs,ys,pc] = rectToCorners( pos0 )
    % return 4 rect corners in real world coords
    [pc,rs,R]=rectInfo( pos0 );
    x0=-rs(1); x1=rs(1); y0=-rs(2); y1=rs(2);
    pts=[x0 y0; x1 y0; x1 y1; x0 y1]*R'+pc(ones(4,1),:);
    xs=pts(:,1); ys=pts(:,2);
  end

  function pos1 = cornersToRect( pos0, x0, y0, x1, y1 )
    % compute pos from 4 corners given in rect coords
    [pc,rs,R] = rectInfo( pos0 );
    p0=[x0 y0]*R'+pc; p1=[x1 y1]*R'+pc;
    pc=(p1+p0)/2; p0=(p0-pc)*R; p1=(p1-pc)*R;
    pos1 = [pc+p0 p1-p0 pos0(5)];
  end

  function setPos( posNew )
    if(isempty(hBnds) || isempty(hPatch)); return; end; L=lims;
    % if corners fall outside lims don't use posNew
    if( ~isempty(L) )
      if( posNew(5)==lims(5) )
        % lims and posNew at same orient (do everything in rect coords)
        [pc,rs,R]=rectInfo(posNew); p0=-rs; p1=rs;
        pts=(rectToCorners(L)-pc(ones(4,1),:))*R;
        L0=[pts(1,1) pts(1,2)]; L1=[pts(2,1) pts(3,2)];
        p0=min(max(p0,L0),L1); p1=max(min(p1,L1),p0);
        posNew=cornersToRect(posNew,p0(1),p0(2),p1(1),p1(2));
      else
        % lims and posNew at diff orient (do everything in lims coords)
        [pc,rs,R]=rectInfo(L); p0=-rs; p1=rs;
        p=(rectToCorners(posNew)-pc(ones(4,1),:))*R; xs=p(:,1); ys=p(:,2);
        valid=[xs>=p0(1) xs<=p1(1) ys>=p0(2) ys<=p1(2)];
        if(~all(valid(:))), return; end
      end
    end
    % draw objects
    pos=posNew; [pts,xs,ys]=rectToCorners(pos);
    vert=[xs ys ones(4,1)]; face=1:4;
    set(hPatch,'Faces',face,'Vertices',vert);
    for i=1:4, ids=mod([i-1 i],4)+1;
      set(hBnds(i),'Xdata',xs(ids),'Ydata',ys(ids));
    end
  end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

  function pnt = getCurPnt()
    pnt = get(hAx,'CurrentPoint');
    pnt = pnt([1,3]);
  end

  function d = axisUnitsPerCentimeter()
    % approximage absolute axes size
    units=get(hAx,'units');
    set(hAx,'units','centimeters');
    cms = get(hAx,'Position');
    cms = max(cms(3:4));
    set(hAx,'units',units);
    % axes size in axes units
    xLim=get(gca,'xLim'); yLim=get(gca,'yLim');
    sizInner = max([xLim(2)-xLim(1),yLim(2)-yLim(1)]);
    % units per centemeter
    d = sizInner/cms;
  end

  function [side,cursor] = getSide( pnt )
    % get pnt in coordintates of center of rectangle
    [pc,rs,R]=rectInfo(pos); pnt=(pnt-pc)*R; th=pos(5);
    % side(i) -1=near lf/tp bnd; 0=in center; +1:near rt/bt bnd
    t = axisUnitsPerCentimeter()*.15; side=[0 0];
    for i=1:2
      ti = min(t,rs(i)/2);
      if( pnt(i)<-rs(i)+ti ), side(i)=-1; % near lf/tp boundary
      elseif( pnt(i)>rs(i)-ti), side(i)=1; % near rt/bt boundary
      end
    end
    % select cursor based on position
    cs={'bottom','botr','right','topr','top','topl','left','botl'};
    a=mod(round((atan2(side(1),side(2))/pi-th/180)*4),8)+1; cursor=cs{a};
  end

  function btnDwn( h, evnt, flag )
    if(isempty(hBnds) || isempty(hPatch)); return; end;
    if(posLock); return; end; if(sizLock); flag=1; end;
    if( flag==-1 ) % create new rectangle
      if(isempty(pos)), anchor=ginput(1); else anchor=pos(1:2); end
      setPos( [anchor 1 1 0] );
      set(hBnds,'Visible','on'); cursor='botr'; flag=0;
    elseif( flag==0 ) % resize (or possibly drag) rectangle
      pnt=getCurPnt(); [anchor,cursor] = getSide( pnt );
      if(all(anchor==0)), btnDwn(h,evnt,1); return; end
    elseif( flag==1 ) % move rectangle
      anchor=getCurPnt(); cursor='fleur';
    else
      assert(false);
    end
    set( hFig, 'Pointer', cursor );
    set( hFig, 'WindowButtonMotionFcn',{@drag,flag,anchor,pos} );
    set( hFig, 'WindowButtonUpFcn', @stopDrag );
  end

  function drag( h, evnt, flag, anchor, pos0 ) %#ok<INUSL>
    if(isempty(hBnds) || isempty(hPatch)); return; end;
    pnt = getCurPnt(); del = pnt-anchor;
    if( flag==1 ) % shift rectangle by del
      setPos( [pos0(1:2)+del pos0(3:5)] );
    else % resize in rectangle coordinate frame
      [pc,rs,R]=rectInfo(pos0); p0=-rs; p1=rs; del=(pnt-pc)*R;
      for i=1:2, if(anchor(i)>0), p1(i)=del(i); end; end
      for i=1:2, if(anchor(i)<0), p0(i)=del(i); end; end
      p0a=min(p0,p1); p1=max(p0,p1); p0=p0a;
      setPos(cornersToRect(pos0,p0(1),p0(2),p1(1),p1(2)));
    end
    drawnow
    if(~isempty(posChnCb)); posChnCb(pos); end;
  end

  function stopDrag( h, evnt ) %#ok<INUSD>
    set( hFig, 'WindowButtonMotionFcn','');
    set( hFig, 'WindowButtonUpFcn','');
    set( hFig, 'Pointer', 'arrow' );
    if(~isempty(posSetCb)); posSetCb(pos); end;
  end

  function deleteFcn( h, evnt ) %#ok<INUSD>
    [posChnCb,posSetCb]=deal([]); hs=[hPatch hBnds];
    for i=1:length(hs), if(ishandle(hs(i))); delete(hs(i)); end; end
    [hBnds,hPatch]=deal([]);
  end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

  function pos0 = getPos(), pos0=pos; end

  function setPosChnCb( f ), posChnCb=f; end

  function setPosSetCb( f ), posSetCb=f; end

  function setPosLock( b ), posLock=b; end

  function setSizLock( b ), sizLock=b; end

  function uistack1( varargin )
    if(isempty(hBnds) || isempty(hPatch)); return; end;
    uistack( [hBnds hPatch], varargin{:} );
  end

end
