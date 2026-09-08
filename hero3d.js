/* Immoscan — diorama 3D réaliste du hero (Three.js vendored, global THREE).
   Textures procédurales (canvas), environnement PMREM pour des réflexions douces.
   Repli automatique sur la démo CSS si WebGL indisponible ou "reduced motion". */
(function(){
  "use strict";
  var wrap = document.getElementById('hero3d');
  var canvas = document.getElementById('hero3d-canvas');
  if(!wrap || !canvas || typeof THREE === 'undefined') return;
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion:reduce)').matches;
  try { var t0 = canvas.getContext('webgl2') || canvas.getContext('webgl'); if(!t0) return; } catch(e){ return; }

  var ACCENT = 0x7c3aed;

  var renderer;
  try { renderer = new THREE.WebGLRenderer({ canvas:canvas, antialias:true, alpha:true, powerPreference:'high-performance' }); }
  catch(e){ return; }
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio||1));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  if(THREE.ACESFilmicToneMapping){ renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.0; }
  if('outputColorSpace' in renderer && THREE.SRGBColorSpace){ renderer.outputColorSpace = THREE.SRGBColorSpace; }
  var maxAniso = renderer.capabilities.getMaxAnisotropy ? renderer.capabilities.getMaxAnisotropy() : 1;

  // ---- Textures procédurales (canvas, aucune ressource externe) ----
  function cnv(w,h){ var c=document.createElement('canvas'); c.width=w; c.height=h; return c; }
  function tex(c, rep){ var t=new THREE.CanvasTexture(c); t.wrapS=t.wrapT=THREE.RepeatWrapping; if(rep) t.repeat.set(rep[0],rep[1]); t.anisotropy=maxAniso; if(THREE.SRGBColorSpace) t.colorSpace=THREE.SRGBColorSpace; return t; }
  function noise(ctx,w,h,amt,alpha){ for(var i=0;i<w*h*amt/100;i++){ var x=Math.random()*w,y=Math.random()*h,g=Math.random()*40-20; ctx.fillStyle='rgba('+(128+g)+','+(128+g)+','+(128+g)+','+(alpha||0.06)+')'; ctx.fillRect(x,y,1,1); } }
  // Parquet
  var woodC=cnv(512,512), wx=woodC.getContext('2d');
  for(var p=0;p<8;p++){ var base=[196,170,132][0]; var shades=['#c9ad82','#c3a679','#cdb187','#bfa073','#c7ab80']; wx.fillStyle=shades[p%shades.length]; wx.fillRect(0,p*64,512,64);
    wx.strokeStyle='rgba(90,66,38,0.35)'; wx.lineWidth=2; wx.strokeRect(0,p*64,512,64);
    for(var g2=0;g2<18;g2++){ wx.strokeStyle='rgba(120,90,55,'+(0.05+Math.random()*0.08)+')'; wx.beginPath(); var yy=p*64+Math.random()*64; wx.moveTo(0,yy); wx.bezierCurveTo(170,yy+ (Math.random()*6-3),340,yy+(Math.random()*6-3),512,yy); wx.stroke(); } }
  var woodTex=tex(woodC,[2,2]);
  // Mur (léger grain)
  var wallC=cnv(256,256), wc=wallC.getContext('2d'); wc.fillStyle='#f4f1ec'; wc.fillRect(0,0,256,256); noise(wc,256,256,60,0.05);
  var wallTex=tex(wallC,[2,2]);
  // Ciel (dégradé pour la fenêtre)
  var skyC=cnv(256,256), sc=skyC.getContext('2d'); var gr=sc.createLinearGradient(0,0,0,256); gr.addColorStop(0,'#aecbff'); gr.addColorStop(0.6,'#d7e7ff'); gr.addColorStop(1,'#f3f7ff'); sc.fillStyle=gr; sc.fillRect(0,0,256,256);
  sc.fillStyle='rgba(255,255,255,0.9)'; sc.beginPath(); sc.arc(70,90,26,0,7); sc.arc(105,95,32,0,7); sc.arc(140,88,24,0,7); sc.fill();
  var skyTex=tex(skyC);
  // Tissu (couette / tapis)
  function fabric(hex){ var c=cnv(128,128), x=c.getContext('2d'); x.fillStyle=hex; x.fillRect(0,0,128,128); noise(x,128,128,120,0.05); return tex(c,[3,3]); }

  var std=function(o){ return new THREE.MeshStandardMaterial(o); };
  function box(w,h,d,m){ var g=new THREE.Mesh(new THREE.BoxGeometry(w,h,d), m); g.castShadow=true; g.receiveShadow=true; return g; }

  var scene = new THREE.Scene();
  var camera = new THREE.PerspectiveCamera(34, 1, 0.1, 100);
  camera.position.set(6.6, 5.2, 7.4); camera.lookAt(0, 0.9, 0);

  // ---- Environnement PMREM (réflexions/ambiance douces, sans HDR externe) ----
  try {
    var pmrem = new THREE.PMREMGenerator(renderer);
    var envS = new THREE.Scene();
    var egc=cnv(64,128), ex=egc.getContext('2d'); var eg=ex.createLinearGradient(0,0,0,128); eg.addColorStop(0,'#dfe8ff'); eg.addColorStop(0.5,'#f3eefb'); eg.addColorStop(1,'#efe7dd'); ex.fillStyle=eg; ex.fillRect(0,0,64,128);
    var envTex=new THREE.CanvasTexture(egc);
    envS.add(new THREE.Mesh(new THREE.SphereGeometry(50,24,16), new THREE.MeshBasicMaterial({map:envTex, side:THREE.BackSide})));
    var panel=new THREE.Mesh(new THREE.PlaneGeometry(26,26), new THREE.MeshBasicMaterial({color:0xffffff})); panel.position.set(12,16,10); panel.lookAt(0,0,0); envS.add(panel);
    scene.environment = pmrem.fromScene(envS, 0.05).texture;
    pmrem.dispose();
  } catch(e){}

  // ---- Lumières (naturelles) ----
  scene.add(new THREE.HemisphereLight(0xffffff, 0xcabfae, 0.35));
  var sun = new THREE.DirectionalLight(0xfff2e0, 2.4);
  sun.position.set(5.5, 8.5, 3.5); sun.castShadow = true;
  sun.shadow.mapSize.set(2048,2048); sun.shadow.camera.near=1; sun.shadow.camera.far=32;
  sun.shadow.camera.left=-8; sun.shadow.camera.right=8; sun.shadow.camera.top=8; sun.shadow.camera.bottom=-8;
  sun.shadow.bias=-0.0004; sun.shadow.radius=6; scene.add(sun);
  var fill = new THREE.DirectionalLight(0xdfe6ff, 0.5); fill.position.set(-6,4,4); scene.add(fill);
  var lampGlow = new THREE.PointLight(0xffd9a0, 8, 6, 2); lampGlow.position.set(0.2,1.5,-2.3); scene.add(lampGlow);

  var room = new THREE.Group(); scene.add(room);

  // Socle
  var base = box(7.4,0.55,7.4, std({color:0xe9e2d6, roughness:0.9})); base.position.y=-0.28; base.castShadow=false; room.add(base);
  var edge = box(7.62,0.12,7.62, std({color:0x9a8f7d, roughness:0.7})); edge.position.y=-0.02; edge.castShadow=false; room.add(edge);

  // Sol parquet
  var floorMat = std({ map:woodTex, roughness:0.55, metalness:0.02, envMapIntensity:0.5 });
  var floor = box(6.6,0.2,6.6, floorMat); floor.position.y=0.1; room.add(floor);

  // Murs + plinthes
  var wallMat = std({ map:wallTex, roughness:0.96, envMapIntensity:0.4 });
  var backW = box(6.6,4.2,0.22, wallMat); backW.position.set(0,2.2,-3.2); room.add(backW);
  var leftW = box(0.22,4.2,6.6, wallMat); leftW.position.set(-3.2,2.2,0); room.add(leftW);
  var plMat = std({color:0xffffff, roughness:0.6});
  var pl1 = box(6.6,0.28,0.14, plMat); pl1.position.set(0,0.34,-3.06); room.add(pl1);
  var pl2 = box(0.14,0.28,6.6, plMat); pl2.position.set(-3.06,0.34,0); room.add(pl2);

  // Fenêtre : ciel + cadre + croisillons + rebord
  var sky = new THREE.Mesh(new THREE.PlaneGeometry(2.3,1.7), std({ map:skyTex, emissive:0xffffff, emissiveMap:skyTex, emissiveIntensity:0.45, roughness:1 }));
  sky.position.set(0.6,2.6,-3.08); room.add(sky);
  var fMat = std({color:0xffffff, roughness:0.5});
  var winTop=box(2.7,0.16,0.16,fMat); winTop.position.set(0.6,3.5,-3.02); room.add(winTop);
  var winBot=box(2.7,0.16,0.16,fMat); winBot.position.set(0.6,1.72,-3.02); room.add(winBot);
  var winL=box(0.16,1.9,0.16,fMat); winL.position.set(-0.68,2.6,-3.02); room.add(winL);
  var winR=box(0.16,1.9,0.16,fMat); winR.position.set(1.88,2.6,-3.02); room.add(winR);
  var mulV=box(0.09,1.8,0.1,fMat); mulV.position.set(0.6,2.6,-3.0); room.add(mulV);
  var mulH=box(2.5,0.09,0.1,fMat); mulH.position.set(0.6,2.6,-3.0); room.add(mulH);
  var sill=box(2.9,0.14,0.4,fMat); sill.position.set(0.6,1.66,-2.92); room.add(sill);

  // Cadre déco sur le mur gauche
  var art=new THREE.Mesh(new THREE.PlaneGeometry(1.2,0.9), std({color:0xcdbff0, roughness:0.8})); art.position.set(-3.08,2.7,-0.4); art.rotation.y=Math.PI/2; room.add(art);
  var artF=box(0.08,1.06,1.36, std({color:0x5a4f45,roughness:0.6})); artF.position.set(-3.06,2.7,-0.4); room.add(artF);

  // Lit avec tête de lit
  var wood=std({color:0x9c7a54, roughness:0.6, envMapIntensity:0.4});
  var head=box(2.7,1.4,0.25, wood); head.position.set(-1.55,1.0,-2.95); room.add(head);
  var bedFrame=box(2.7,0.5,3.1, wood); bedFrame.position.set(-1.55,0.45,-1.3); room.add(bedFrame);
  var mattress=box(2.5,0.4,2.9, std({color:0xf3f0ea, roughness:0.9})); mattress.position.set(-1.55,0.82,-1.3); room.add(mattress);
  var quilt=box(2.54,0.16,1.9, std({map:fabric('#8b93c9'), roughness:0.95})); quilt.position.set(-1.55,1.0,-0.7); room.add(quilt);
  var pil1=box(1.05,0.24,0.62, std({color:0xffffff,roughness:0.85})); pil1.position.set(-2.05,1.06,-2.2); room.add(pil1);
  var pil2=box(1.05,0.24,0.62, std({color:0xf1eef8,roughness:0.85})); pil2.position.set(-0.95,1.06,-2.2); room.add(pil2);

  // Chevet + lampe
  var stand=box(0.72,0.72,0.72, wood); stand.position.set(0.2,0.46,-2.35); room.add(stand);
  var lampP=new THREE.Mesh(new THREE.CylinderGeometry(0.05,0.06,0.5,12), std({color:0x8a7bbf,metalness:0.4,roughness:0.4})); lampP.position.set(0.2,1.07,-2.35); lampP.castShadow=true; room.add(lampP);
  var lampH=new THREE.Mesh(new THREE.ConeGeometry(0.28,0.34,20), std({color:0xfff2d6, emissive:0xffcf87, emissiveIntensity:0.6, roughness:0.7})); lampH.position.set(0.2,1.44,-2.35); lampH.castShadow=true; room.add(lampH);

  // Tapis
  var rug=box(3.1,0.05,2.2, std({map:fabric('#8258d6'), roughness:0.98})); rug.position.set(0.4,0.22,0.7); room.add(rug);

  // Plante
  var pot=new THREE.Mesh(new THREE.CylinderGeometry(0.3,0.24,0.55,20), std({color:0xb5764f, roughness:0.7})); pot.position.set(2.2,0.48,2.0); pot.castShadow=true; room.add(pot);
  var foliage=std({color:0x3f9d6d, roughness:0.85});
  [[0,1.15,0,0.62],[0.28,1.35,0.15,0.4],[-0.25,1.3,-0.1,0.42],[0.05,1.55,0,0.34]].forEach(function(f){ var l=new THREE.Mesh(new THREE.IcosahedronGeometry(f[3],0), foliage); l.position.set(2.2+f[0],f[1],2.0+f[2]); l.castShadow=true; room.add(l); });

  // Balayage lumineux discret (touche "scan", très léger)
  var beamMat=new THREE.MeshBasicMaterial({ color:0xffffff, transparent:true, opacity:0.0, blending:THREE.AdditiveBlending, depthWrite:false, side:THREE.DoubleSide });
  var beam=new THREE.Mesh(new THREE.PlaneGeometry(6.2,0.9), beamMat); beam.rotation.x=-Math.PI/2; beam.position.y=0.24; room.add(beam);

  // Ombre de contact
  var contact=new THREE.Mesh(new THREE.CircleGeometry(4.4,44), new THREE.MeshBasicMaterial({color:0x2a1f14, transparent:true, opacity:0.16}));
  contact.rotation.x=-Math.PI/2; contact.position.y=-0.6; scene.add(contact);

  // ---- Interaction ----
  var autoRot = reduce ? 0 : 0.10;
  var targetY=0.6, curY=0.6, targetX=0.02, curX=0.02, dragging=false, lastX=0, lastY=0;
  function down(e){ dragging=true; var p=e.touches?e.touches[0]:e; lastX=p.clientX; lastY=p.clientY; wrap.classList.add('grab'); }
  function move(e){ if(!dragging) return; var p=e.touches?e.touches[0]:e; targetY+=(p.clientX-lastX)*0.008; targetX+=(p.clientY-lastY)*0.004; targetX=Math.max(-0.1,Math.min(0.45,targetX)); lastX=p.clientX; lastY=p.clientY; if(e.cancelable&&e.touches) e.preventDefault(); }
  function up(){ dragging=false; wrap.classList.remove('grab'); }
  canvas.addEventListener('mousedown',down); window.addEventListener('mousemove',move); window.addEventListener('mouseup',up);
  canvas.addEventListener('touchstart',down,{passive:true}); canvas.addEventListener('touchmove',move,{passive:false}); window.addEventListener('touchend',up);

  function resize(){ var w=canvas.clientWidth||wrap.clientWidth, h=canvas.clientHeight||440; if(!w||!h) return; renderer.setSize(w,h,false); camera.aspect=w/h; camera.updateProjectionMatrix(); }

  var clock=new THREE.Clock(), t=0, running=false, rafId=null;
  function frame(){
    if(!running) return; rafId=requestAnimationFrame(frame);
    var dt=Math.min(0.05, clock.getDelta()); t+=dt;
    if(!dragging) targetY+=autoRot*dt;
    curY+=(targetY-curY)*0.07; curX+=(targetX-curX)*0.07;
    room.rotation.y=curY; room.rotation.x=curX;
    // balayage doux toutes les ~7 s
    var cyc=(t*0.14)%1; beam.position.y=0.24+cyc*3.6; beamMat.opacity=Math.sin(cyc*Math.PI)*0.10;
    renderer.render(scene,camera);
  }
  function start(){ if(!running){ running=true; clock.getDelta(); frame(); } }
  function stop(){ running=false; if(rafId) cancelAnimationFrame(rafId); }

  wrap.classList.add('on'); resize(); window.addEventListener('resize',resize);
  document.addEventListener('visibilitychange', function(){ document.hidden?stop():start(); });
  if('IntersectionObserver' in window){ new IntersectionObserver(function(en){ en.forEach(function(e){ e.isIntersecting?start():stop(); }); },{threshold:0.05}).observe(wrap); }
  start();
  if(reduce){ stop(); renderer.render(scene,camera); }
})();
