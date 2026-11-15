// The promo background: warm paper with a field of red halftone dots that drifts on domain-warped noise,
// denser toward the bottom right (the store creatives' red triangle). One draw per call, so a frame renderer can
// step time exactly. Shared by promo.html (video) and poster.html (stills).
//   const bg = PromoShader(canvas); bg.draw({ time, flood, burst: [x, y, progress], dots })
// time: seconds. flood: 0 = mostly paper, 1 = mostly red. burst: a shockwave ring from uv (x, y; top-left origin)
// with progress 0..1, or null. dots: halftone cells across the short side.
function PromoShader(canvas) {
  const gl = canvas.getContext("webgl", { preserveDrawingBuffer: true, antialias: false });
  const vs = `attribute vec2 p; void main(){ gl_Position = vec4(p, 0., 1.); }`;
  const fs = `
precision highp float;
uniform vec2 uRes; uniform float uTime; uniform float uFlood; uniform vec3 uBurst; uniform float uDots;
const vec3 PAPER = vec3(.925, .886, .804);
const vec3 RED = vec3(.831, .149, .106);
const vec3 INK = vec3(.067);
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){
  vec2 i = floor(p), f = fract(p), u = f * f * (3. - 2. * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p){
  float v = 0., a = .5;
  for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= .5; }
  return v;
}
// Field value at a point in short-side units: how much red ink lands there.
float field(vec2 p, float t){
  vec2 q = vec2(fbm(p * 1.3 + vec2(0., t * .06)), fbm(p * 1.3 + vec2(5.2, 1.3) - t * .05));
  float n = fbm(p * 1.6 + 1.9 * q + vec2(t * .03, 0.));
  float diag = dot(p, normalize(vec2(1., -1.)));           // + toward the bottom right
  return n - .62 + diag * .75 + uFlood * 1.6;
}
void main(){
  vec2 frag = gl_FragCoord.xy;
  vec2 p = (frag - .5 * uRes) / min(uRes.x, uRes.y);
  // Shockwave: displace along a thin expanding ring.
  if (uBurst.z > 0. && uBurst.z < 1.) {
    vec2 b = (vec2(uBurst.x, 1. - uBurst.y) * uRes - .5 * uRes) / min(uRes.x, uRes.y);
    vec2 d = p - b; float r = length(d), R = uBurst.z * 1.9;
    float w = exp(-pow((r - R) * 9., 2.)) * (1. - uBurst.z);
    p -= normalize(d + 1e-5) * w * .09;
  }
  // Halftone on a 45° grid.
  float cell = 1. / uDots;
  mat2 rot = mat2(.7071, -.7071, .7071, .7071);
  vec2 g = rot * p / cell;
  vec2 c = floor(g) + .5;
  vec2 center = mat2(.7071, .7071, -.7071, .7071) * (c * cell);  // inverse rotation
  float v = clamp(field(center, uTime), 0., 1.);
  float rad = sqrt(v) * .62;                              // in cell units; > .5 merges into solid ink
  float dist = length(g - c);
  float aa = 1.2 / (cell * min(uRes.x, uRes.y));
  float dot_ = 1. - smoothstep(rad - aa, rad + aa, dist);
  vec3 col = mix(PAPER, RED, dot_);
  // A few ink specks where the field is dense, like misregistered print.
  float speck = step(.985, hash(c + 3.1)) * step(.55, v);
  col = mix(col, INK, speck * (1. - smoothstep(.18 - aa, .18 + aa, dist)));
  // Paper grain.
  col += (hash(frag) - .5) * .035;                          // static, so the video compresses well
  gl_FragColor = vec4(col, 1.);
}`;
  const sh = (type, s) => {
    const o = gl.createShader(type); gl.shaderSource(o, s); gl.compileShader(o);
    if (!gl.getShaderParameter(o, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(o));
    return o;
  };
  const prog = gl.createProgram();
  gl.attachShader(prog, sh(gl.VERTEX_SHADER, vs)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, fs));
  gl.linkProgram(prog); gl.useProgram(prog);
  const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(prog, "p"); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  const u = n => gl.getUniformLocation(prog, n);
  const U = { res: u("uRes"), time: u("uTime"), flood: u("uFlood"), burst: u("uBurst"), dots: u("uDots") };
  return {
    draw({ time = 0, flood = 0, burst = null, dots = 90 } = {}) {
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.uniform2f(U.res, canvas.width, canvas.height);
      gl.uniform1f(U.time, time); gl.uniform1f(U.flood, flood); gl.uniform1f(U.dots, dots);
      gl.uniform3f(U.burst, ...(burst || [0, 0, 0]));
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    },
  };
}
if (typeof module !== "undefined") module.exports = PromoShader;
