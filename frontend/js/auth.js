// Autenticación con Amazon Cognito — vanilla JS, sin SDK ni bundler.
// Los valores los inyecta deploy.sh vía window.AGRO_CONFIG.

const _cfg        = window.AGRO_CONFIG || {};
const USER_POOL_ID = _cfg.userPoolId || '';
const CLIENT_ID    = _cfg.clientId   || '';
const REGION       = USER_POOL_ID.split('_')[0];
const ENDPOINT     = `https://cognito-idp.${REGION}.amazonaws.com/`;

const KEYS = {
  id:      'agro_id_token',
  access:  'agro_access_token',
  refresh: 'agro_refresh_token'
};

function cognitoPost(target, body) {
  return fetch(ENDPOINT, {
    method:  'POST',
    headers: {
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Target': `AWSCognitoIdentityProviderService.${target}`
    },
    body: JSON.stringify(body)
  });
}

function storeTokens({ IdToken, AccessToken, RefreshToken }) {
  sessionStorage.setItem(KEYS.id,     IdToken);
  sessionStorage.setItem(KEYS.access, AccessToken);
  if (RefreshToken) sessionStorage.setItem(KEYS.refresh, RefreshToken);
}

function parseJwt(token) {
  try { return JSON.parse(atob(token.split('.')[1])); } catch { return null; }
}

export async function signUp(email, password) {
  const res  = await cognitoPost('SignUp', {
    ClientId: CLIENT_ID,
    Username: email,
    Password: password,
    UserAttributes: [{ Name: 'email', Value: email }]
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.message || data.__type || 'Error al registrar');
  return { ok: true, userConfirmed: data.UserConfirmed };
}

export async function confirmSignUp(email, code) {
  const res  = await cognitoPost('ConfirmSignUp', {
    ClientId:         CLIENT_ID,
    Username:         email,
    ConfirmationCode: code
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.message || data.__type || 'Código incorrecto');
}

export async function signIn(email, password) {
  const res  = await cognitoPost('InitiateAuth', {
    AuthFlow:       'USER_PASSWORD_AUTH',
    ClientId:       CLIENT_ID,
    AuthParameters: { USERNAME: email, PASSWORD: password }
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.message || data.__type || 'Error al autenticar');
  if (data.ChallengeName === 'NEW_PASSWORD_REQUIRED') {
    return { ok: false, challenge: 'NEW_PASSWORD_REQUIRED', session: data.Session, email };
  }
  storeTokens(data.AuthenticationResult);
  return { ok: true };
}

export async function completeNewPassword(email, session, newPassword) {
  const res  = await cognitoPost('RespondToAuthChallenge', {
    ChallengeName:      'NEW_PASSWORD_REQUIRED',
    ClientId:           CLIENT_ID,
    Session:            session,
    ChallengeResponses: { USERNAME: email, NEW_PASSWORD: newPassword }
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.message || data.__type || 'No se pudo establecer la contraseña');
  storeTokens(data.AuthenticationResult);
}

export function getSession() {
  const idToken = sessionStorage.getItem(KEYS.id);
  if (!idToken) return null;
  const payload = parseJwt(idToken);
  if (!payload || payload.exp * 1000 < Date.now()) { signOut(); return null; }
  const name = (payload.given_name || payload.email?.split('@')[0] || 'user').trim();
  return { idToken, email: payload.email, name };
}

export function signOut() {
  Object.values(KEYS).forEach(k => sessionStorage.removeItem(k));
}
