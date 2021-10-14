#version 300 es

#define keyPadding 0.011f
#define keyScale 2.7f
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 128;
const float FOV = 45.0;
const float FOV_TAN = tan(45.0);
const float EPSILON = 1e-6;

const vec3 EYE = vec3(0.0, 0.0, -10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_DIR = vec3(-1.0, -1.0, -2.0);

const vec3 ebCut = vec3(0.062, -0.27f, 0.f) / keyScale;
const vec3 ebCutB = vec3(0.04, 0.45, 0.121) / keyScale;
const vec3 whiteKeyBox = vec3(0.1, 0.71, 0.12) / keyScale;
const vec3 keyStep = vec3(0.2f + keyPadding, 0.f, 0.f) / keyScale;

struct Surface {
  float distance;
  vec3 color;
};

Surface createSurface() {
  Surface surf;
  surf.distance = 9999999.f;
  surf.color = vec3(0.f, 0.f, 0.f);
  return surf;
}

Surface mins(Surface a, Surface b) {
  if (a.distance < b.distance) {
    return a;
  } else {
    return b;
  }
}

Surface maxs(Surface a, Surface b) {
  if (a.distance > b.distance) {
    return a;
  } else {
    return b;
  }
}

struct Ray 
{
  vec3 origin;
  vec3 direction;
};

struct Intersection 
{
  vec3 position;
  vec3 normal;
  float distance_t;
  int material_id;
  vec3 color;
};

// --- Geometry helpers ---
float smoothSubtraction(float d1, float d2, float k)  {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}

float lengthInf(vec3 p) {
  return max(p.x, max(p.y, p.y));
}

vec3 flipX(vec3 p) {
  return vec3(-p.x, p.y, p.z);
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

mat3 rotationMatrix(vec3 axis, float angle)
{
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    return mat3(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c);
}

vec3 translateTo(vec3 p, vec3 c) {
  return p - c;
}

vec3 rotateAround(vec3 p, vec3 axis, float angle) {
  return rotationMatrix(axis, angle) * p;
}

// L2-Norm SDFs
float sdCappedCylinder(vec3 p, float h, float r) {
  vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(h,r);
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdfSphere(vec3 query_position, vec3 position, float radius) {
  return length(query_position - position) - radius;
}

float sdfRoundBox(vec3 p, vec3 b, float r) {
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdfBox( vec3 p, vec3 b ) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

Surface sdfEbonyKey(vec3 p) {
  Surface s;
  s.distance = sdfBox(p, vec3(0.05, 0.45, 0.18) / keyScale);
  s.color = vec3(0.09f, 0.09f, 0.09f);
  return s;
}

Surface sdfEBKey(vec3 p) {
  Surface s;
  vec3 pt = p + ebCut;
  float d1 = -sdfBox(pt, ebCutB);
  float d2 = sdfBox(p, whiteKeyBox);
  s.distance = d1 > d2 ? d1 : d2;
  s.color = vec3(0.98, 0.98, 0.98);
  return s;
}

Surface sdfCFKey(vec3 p) {
  return sdfEBKey(p - vec3(p.x * 2.f - whiteKeyBox.x, 0.f, 0.f));
}

float expImpulse(float x, float k) {
    float h = k * x;
    return h * exp(1.0 - h);
}

Surface sdfDKey(vec3 p) {
  Surface s;
  float mod = (1. + cos(u_Time / 4.f)) / 25.f;
  p.z -= expImpulse(mod, 1.f / 25.f) * 4.5f;
  vec3 pt = p + vec3(0.085, -0.27f, 0.f) / keyScale;
  float leftBox = sdfBox(pt, vec3(0.02, 0.45, 0.121) / keyScale);
  pt = p + vec3(-0.089, -0.27f, 0.f) / keyScale;
  float rightBox = sdfBox(pt, vec3(0.02, 0.45, 0.121) / keyScale);
  s.distance = max(-rightBox, max(-leftBox, sdfBox(p, vec3(0.1, 0.71, 0.12) / keyScale)));
  s.color = vec3(0.98, 0.98, 0.98);
  return s;
}

Surface sdfGKey(vec3 p) {
  Surface s;
  vec3 pt = p + vec3(0.085, -0.27f, 0.f) / keyScale;
  float leftBox = sdfBox(pt, vec3(0.018, 0.45, 0.121) / keyScale);
  pt = p + vec3(-0.076, -0.27f, 0.f) / keyScale;
  float rightBox = sdfBox(pt, vec3(0.025, 0.45, 0.121) / keyScale);
  s.distance = max(-rightBox, max(-leftBox, sdfBox(p, vec3(0.1, 0.71, 0.12) / keyScale)));
  s.color = vec3(0.98, 0.98, 0.98);
  return s;
}

Surface sdfAKey(vec3 p) {
  return sdfGKey(p - vec3(p.x * 2.f, 0.f, 0.f));
}

Surface sdfMusicStand(vec3 p) {
  Surface s;
  vec3 p2 = p + vec3(0.f, 0.58f, 0.5f);
  p2 = rotateAround(p2, vec3(1.f, 0.f, 0.f), 0.3);
  s.distance = smoothSubtraction(
    sdCappedCylinder(p2 + vec3(-1.46f, 0.f, 0.2f), 0.2, 0.022),
    smoothSubtraction(
      sdCappedCylinder(p2 + vec3(1.46f, 0.f, 0.2f), 0.2, 0.022), 
      sdfBox(p2, vec3(1.5f, 0.02f, 0.25f)),
      0.1), 0.1);

  s.color = vec3(0.09, 0.09, 0.09);
  return s;
}

// For center-positioned objects
vec3 repeatX(vec3 p, float period, float l, float u) {
  vec3 p2 = p;
  p2.x = p.x - period * clamp(round(p.x / period), l, u);
  return p2;
}

// For top-left-near positioned objects
vec3 repeatX2(vec3 p, float period, float l, float u) {
  vec3 p2 = p;
  p2.x = p.x - period * clamp(floor(p.x / period), l, u);
  return p2;
}

Surface sdfOctave2(vec3 p) {
  vec3 ip = p - vec3(0.18, 0.28, -0.063) / keyScale;

  // Ivory Keys
  vec3 q = repeatX(p, keyStep.x * 3.f, 0.f, 1.f);
  Surface cf = sdfCFKey(q);
  p -= keyStep + vec3(0.04f, 0.f,0.f);
  Surface d = sdfDKey(p);
  p -= keyStep;
  q = repeatX(p, keyStep.x * 4.f, 0.f, 1.f);
  Surface eb = sdfEBKey(q);
  p -= 2.f * keyStep;
  Surface g = sdfGKey(p);
  p -= keyStep;
  Surface a = sdfAKey(p);

  // Ebony Keys
  q = repeatX(ip, 0.255 / keyScale, 0.f, 1.f);
  Surface csds = sdfEbonyKey(q);
  ip.x -= (0.38 + 0.255) / keyScale;
  q = repeatX(ip, 0.24 / keyScale, 0.f, 2.f);
  Surface fsgsas = sdfEbonyKey(q);
  return mins(fsgsas, mins(csds, mins(a, mins(g, mins(eb, mins(cf, d))))));
}


Surface sdfKeys2(vec3 p, int octaves) {
  vec3 q = repeatX2(p, keyStep.x * 7.f, 0.f, float(octaves));
  return sdfOctave2(q);
}

Surface sdfFrame(vec3 p) {
  Surface s;
  s.color = vec3(0.3f, 0.3f, 0.3f);
  vec3 mainB = vec3(7.f, 2.f, 6.f) / 4.f;
  vec3 sideB = vec3(0.05, 0.9, 0.9);
  vec3 frontB = vec3(mainB.x, sideB.x, 0.2);
  float top = sdfRoundBox(p + vec3(0.f, 0.f, 1.5f), vec3(7.1f, 2.1f, 0.1f) / 4.f, 0.01);
  float bottom = 
    sdfBox(p + vec3(0.f, 1.f, -0.1f), vec3(1.7f, 0.3f, 0.1f));
  s.distance = min(
    sdfBox(p + vec3(0.f, mainB.y + sideB.y - frontB.y * 3.f, 0.f), frontB), 
    smin(
      sdfRoundBox(p - flipX(mainB) + flipX(sideB), sideB, 0.01), 
      smin(sdfRoundBox(p - mainB + sideB, sideB, 0.01), sdfBox(p, mainB), 0.1), 0.1));

    s.distance = smin(top, s.distance, 0.1);
    s.distance = min(s.distance, bottom);
    return s;
}

Surface sdfPiano(vec3 p) {
  float box = sdfBox(p + vec3(0.f, 1.f, 0.2f), vec3(1.7f, 0.3f, 0.6f));
  Surface keys;
  keys.distance = 999999.f;
  if (box < EPSILON) {
    keys = sdfKeys2(p + vec3(1.63f, 0.95f, 0.2f), 6);
  }

  return mins(sdfMusicStand(p), mins(keys, sdfFrame(p)));
}

Surface sceneSDF(vec3 p) {
  return sdfPiano(p - vec3(0.f,1.f,0.f));
}

const float d = 0.001f;
vec3 sceneSDFGrad(vec3 queryPos) {
  vec3 diffVec = vec3(d, 0.f, 0.f);
  return normalize(vec3(
      sceneSDF(queryPos + diffVec).distance - sceneSDF(queryPos - diffVec).distance ,
      sceneSDF(queryPos + diffVec.yxz).distance  - sceneSDF(queryPos - diffVec.yxz).distance ,
      sceneSDF(queryPos + diffVec.zyx).distance  - sceneSDF(queryPos - diffVec.zyx).distance 
    ));
}

Ray getRay(vec2 uv)
{
  Ray r;
  
  vec3 look = normalize(u_Ref - u_Eye);
  vec3 camera_RIGHT = normalize(cross(u_Up, look));
  vec3 camera_UP = u_Up;
  
  float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
  vec3 screen_vertical = camera_UP * FOV_TAN; 
  vec3 screen_horizontal = camera_RIGHT * aspect_ratio * FOV_TAN;
  vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
  
  r.origin = (screen_point + u_Eye) / 2.f;
  r.direction = normalize(screen_point - u_Eye);

  return r;
}

const float MIN_STEP = EPSILON * 2.f;
Intersection getRaymarchedIntersection(vec2 uv)
{
  Intersection intersection;
  intersection.distance_t = -1.0;
  Ray ray = getRay(uv);

  float distance_t = 0.f;
  for (int step = 0; step < MAX_RAY_STEPS; step++) {
    vec3 point = ray.origin + ray.direction * distance_t;
    Surface s = sceneSDF(point);

    if (s.distance < EPSILON) {
      intersection.distance_t = s.distance;
      intersection.position = point;
      intersection.normal = sceneSDFGrad(point);
      intersection.color = s.color;

      return intersection;
    }

    distance_t += max(s.distance, MIN_STEP);

    if (distance_t > 100.f) {
      break;
    }
  }

  return intersection;
}

const vec3 light = vec3(10.f, 14.f, 3.f);
vec3 getSceneColor(vec2 uv) {
  Intersection intersection = getRaymarchedIntersection(uv);

  if (abs(intersection.distance_t) < EPSILON)
  {
      float diffuseTerm = dot(intersection.normal, normalize(u_Eye - intersection.position));
      diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);

      return intersection.color * (diffuseTerm + 0.2);
  }

  return vec3(0.7, 0.2, 0.2);
}

void main() {
  // Time varying pixel color
  vec3 col = getSceneColor(fs_Pos);

  // Output to screen
  out_Col = vec4(col, 1.0);
}