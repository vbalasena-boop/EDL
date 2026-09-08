/* Immoscan — diorama 3D du hero (Three.js vendored, global THREE).
   Repli automatique sur la démo CSS si WebGL indisponible ou "reduced motion". */
(function(){
  "use strict";
  var wrap = document.getElementById('hero3d');
  var canvas = document.getElementById('hero3d-canvas');
  if(!wrap || !canvas || typeof THREE === 'undefined') return;
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion:reduce)').matches;

  // Test WebGL
  try { var gl = canvas.getContext('webgl2') || canvas.getContext('webgl'); if(!gl) return; } catch(e){ return; }

  var css = getComputedStyle(document.documentElement);
  var C = function(n,f){ var v=(css.getPropertyValue(n)||'').trim(); return v||f; };
  var ACCENT = 0x7c3aed, ACCENT2 = 0x6366f1;

  var renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas:canvas, antialias:true, alpha:true, powerPreference:'high-performance' });
  } catch(e){ return; }
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio||1));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  if(THREE.ACESFilmicToneMapping){ renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.05; }
  if('outputColorSpace' in renderer && THREE.SRGBColorSpace){ renderer.outputColorSpace = THREE.SRGBColorSpace; }

  var scene = new THREE.Scene();
  var camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100);
  camera.position.set(6.4, 5.0, 7.2);
  camera.lookAt(0, 0.6, 0);

  // Lumières
  scene.add(new THREE.HemisphereLight(0xffffff, 0x9a86c9, 0.75));
  var key = new THREE.DirectionalLight(0xffffff, 2.1);
  key.position.set(6, 9, 5);
  key.castShadow = true;
  key.shadow.mapSize.set(1024,1024);
  key.shadow.camera.near = 1; key.shadow.camera.far = 30;
  key.shadow.camera.left=-8; key.shadow.camera.right=8; key.shadow.camera.top=8; key.shadow.camera.bottom=-8;
  key.shadow.bias = -0.0004; key.shadow.radius = 4;
  scene.add(key);
  var rim = new THREE.PointLight(ACCENT, 40, 30, 2); rim.position.set(-5,4,-3); scene.add(rim);
  var warm = new THREE.PointLight(0xffd9a0, 14, 18, 2); warm.position.set(1.6,2.4,1.2); scene.add(warm);

  var mat = function(color,rough,metal){ return new THREE.MeshStandardMaterial({ color:color, roughness:rough==null?0.85:rough, metalness:metal||0 }); };
  var box = function(w,h,d,m){ var g=new THREE.Mesh(new THREE.BoxGeometry(w,h,d), m); g.castShadow=true; g.receiveShadow=true; return g; };

  var room = new THREE.Group();
  scene.add(room);

  // Socle flottant (diorama)
  var base = box(7.4, 0.6, 7.4, mat(0xe7e1f7, 0.95));
  base.position.y = -0.3; base.castShadow=false; room.add(base);
  var baseEdge = box(7.6, 0.14, 7.6, mat(ACCENT2, 0.5, 0.1)); baseEdge.position.y=-0.02; baseEdge.castShadow=false; room.add(baseEdge);

  // Sol
  var floor = box(6.6, 0.2, 6.6, mat(0xf3eefb, 0.9)); floor.position.y=0.1; room.add(floor);
  // Tapis
  var rug = box(3.0, 0.06, 2.2, mat(ACCENT, 0.8)); rug.position.set(0.3,0.22,0.6); room.add(rug);

  // Murs (deux, en L pour la vue iso)
  var wallM = mat(0xffffff, 0.95);
  var backW = box(6.6, 4.0, 0.25, wallM); backW.position.set(0, 2.1, -3.2); room.add(backW);
  var leftW = box(0.25, 4.0, 6.6, wallM); leftW.position.set(-3.2, 2.1, 0); room.add(leftW);

  // Fenêtre (cadre + vitre lumineuse) sur le mur du fond
  var winFrame = box(2.4, 1.8, 0.14, mat(0xffffff, 0.6)); winFrame.position.set(0.7, 2.5, -3.05); room.add(winFrame);
  var glass = new THREE.Mesh(new THREE.PlaneGeometry(2.0, 1.44), new THREE.MeshStandardMaterial({ color:0xbfe0ff, emissive:0x8fc2ff, emissiveIntensity:0.6, roughness:0.3 }));
  glass.position.set(0.7, 2.5, -2.97); room.add(glass);

  // Lit
  var bed = box(2.6, 0.5, 3.0, mat(0xbdb2e0, 0.9)); bed.position.set(-1.6, 0.45, -1.0); room.add(bed);
  var mattress = box(2.4, 0.35, 2.8, mat(0xffffff, 0.85)); mattress.position.set(-1.6, 0.8, -1.0); room.add(mattress);
  var pillow = box(1.0, 0.22, 0.6, mat(0xece8fb, 0.8)); pillow.position.set(-1.6, 1.02, -2.05); room.add(pillow);
  var quilt = box(2.42, 0.12, 1.7, mat(ACCENT2, 0.85)); quilt.position.set(-1.6, 1.0, -0.4); room.add(quilt);

  // Table de chevet + lampe
  var stand = box(0.7,0.7,0.7, mat(0xcabfe8,0.9)); stand.position.set(0.2,0.45,-2.3); room.add(stand);
  var lampP = box(0.1,0.5,0.1, mat(0x8a7bbf,0.6)); lampP.position.set(0.2,1.05,-2.3); room.add(lampP);
  var lampH = new THREE.Mesh(new THREE.ConeGeometry(0.28,0.35,16), new THREE.MeshStandardMaterial({color:0xfff2d6, emissive:0xffcf87, emissiveIntensity:0.7, roughness:0.6}));
  lampH.position.set(0.2,1.42,-2.3); lampH.castShadow=true; room.add(lampH);

  // Plante
  var pot = new THREE.Mesh(new THREE.CylinderGeometry(0.28,0.22,0.5,16), mat(0xb08968,0.9)); pot.position.set(2.1,0.45,1.9); pot.castShadow=true; room.add(pot);
  var leaf = new THREE.Mesh(new THREE.IcosahedronGeometry(0.6,0), mat(0x4caf7d,0.8)); leaf.position.set(2.1,1.2,1.9); leaf.castShadow=true; room.add(leaf);

  // Faisceau de scan (balaye la pièce) — évoque l'analyse par photo
  var beamMat = new THREE.MeshBasicMaterial({ color:ACCENT, transparent:true, opacity:0.35, blending:THREE.AdditiveBlending, side:THREE.DoubleSide, depthWrite:false });
  var beam = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 6.4), beamMat);
  beam.rotation.x = -Math.PI/2; beam.position.y = 0.3; room.add(beam);

  // Ombre de contact douce sous le diorama
  var shadowMat = new THREE.MeshBasicMaterial({ color:0x2a1a4a, transparent:true, opacity:0.18 });
  var contact = new THREE.Mesh(new THREE.CircleGeometry(4.2, 40), shadowMat);
  contact.rotation.x = -Math.PI/2; contact.position.y = -0.62; scene.add(contact);

  // Interaction souris / tactile : rotation
  var autoRot = reduce ? 0 : 0.15;
  var targetY = 0.5, curY = 0.5, targetX = 0.0, curX = 0.0, dragging=false, lastX=0, lastY=0;
  function down(e){ dragging=true; var p=e.touches?e.touches[0]:e; lastX=p.clientX; lastY=p.clientY; wrap.classList.add('grab'); }
  function move(e){ if(!dragging) return; var p=e.touches?e.touches[0]:e; targetY += (p.clientX-lastX)*0.008; targetX += (p.clientY-lastY)*0.004; targetX=Math.max(-0.15,Math.min(0.5,targetX)); lastX=p.clientX; lastY=p.clientY; if(e.cancelable && e.touches) e.preventDefault(); }
  function up(){ dragging=false; wrap.classList.remove('grab'); }
  canvas.addEventListener('mousedown',down); window.addEventListener('mousemove',move); window.addEventListener('mouseup',up);
  canvas.addEventListener('touchstart',down,{passive:true}); canvas.addEventListener('touchmove',move,{passive:false}); window.addEventListener('touchend',up);

  function resize(){
    var w = canvas.clientWidth || wrap.clientWidth, h = canvas.clientHeight || 440;
    if(!w||!h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w/h; camera.updateProjectionMatrix();
  }

  var clock = new THREE.Clock();
  var t = 0, running = true, rafId = null;
  function frame(){
    if(!running) return;
    rafId = requestAnimationFrame(frame);
    var dt = Math.min(0.05, clock.getDelta()); t += dt;
    if(!dragging) targetY += autoRot*dt;
    curY += (targetY-curY)*0.08; curX += (targetX-curX)*0.08;
    room.rotation.y = curY; room.rotation.x = curX;
    // scan
    var s = (Math.sin(t*0.9)*0.5+0.5);
    beam.position.y = 0.3 + s*3.6;
    beamMat.opacity = 0.12 + (1-Math.abs(Math.sin(t*0.9)))*0.30;
    rim.intensity = 34 + Math.sin(t*1.3)*10;
    renderer.render(scene, camera);
  }
  function start(){ if(!running){ running=true; clock.getDelta(); frame(); } }
  function stop(){ running=false; if(rafId) cancelAnimationFrame(rafId); }

  // Active le 3D, masque la démo CSS
  wrap.classList.add('on');
  resize();
  window.addEventListener('resize', resize);
  document.addEventListener('visibilitychange', function(){ document.hidden ? stop() : start(); });
  if('IntersectionObserver' in window){
    new IntersectionObserver(function(en){ en.forEach(function(e){ e.isIntersecting ? start() : stop(); }); },{threshold:0.05}).observe(wrap);
  }
  running=true; frame();
  if(reduce){ stop(); renderer.render(scene,camera); } // statique si reduced-motion
})();
