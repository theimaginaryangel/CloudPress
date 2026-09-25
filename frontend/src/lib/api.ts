const API_URL = 'https://yd1h3zhgqf.execute-api.us-east-1.amazonaws.com';

export interface HealthMetrics {
  disk_usage?: string;
  core_updates?: number;
  plugin_updates?: number;
  ssl_days_remaining?: number;
  admins?: string[];
  last_checked?: number;
}

export interface Site {
  site_id: string;
  domain: string;
  instance_size: string;
  status: 'PROVISIONING' | 'AVAILABLE' | 'FAILED' | 'DESTROYING';
  created_at?: number | string;
  alb_dns_name?: string;
  public_url?: string;
  health_metrics?: HealthMetrics;
}

export function getAdminKey(): string {
  if (typeof window !== 'undefined') {
    return localStorage.getItem('cloudpress_admin_key') || '';
  }
  return '';
}

export function setAdminKey(key: string): void {
  if (typeof window !== 'undefined') {
    if (key.trim()) {
      localStorage.setItem('cloudpress_admin_key', key.trim());
    } else {
      localStorage.removeItem('cloudpress_admin_key');
    }
  }
}

export function clearAdminKey(): void {
  if (typeof window !== 'undefined') {
    localStorage.removeItem('cloudpress_admin_key');
  }
}

function getAuthHeaders(explicitKey?: string): Record<string, string> {
  const key = explicitKey || getAdminKey();
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (key) {
    headers['x-api-key'] = key;
  }
  return headers;
}

export async function getSites(): Promise<Site[]> {
  const res = await fetch(`${API_URL}/sites`, { cache: 'no-store' });
  if (!res.ok) throw new Error('Failed to fetch sites');
  return res.json();
}

export async function getSite(siteId: string): Promise<Site> {
  const res = await fetch(`${API_URL}/sites/${siteId}`, { cache: 'no-store' });
  if (!res.ok) throw new Error('Failed to fetch site');
  return res.json();
}

export async function createSite(siteId: string, domain: string, instanceSize: string = 't3.micro', adminKey?: string) {
  const res = await fetch(`${API_URL}/sites`, {
    method: 'POST',
    headers: getAuthHeaders(adminKey),
    body: JSON.stringify({ site_id: siteId, domain, instance_size: instanceSize }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || (res.status === 401 ? 'Unauthorized: Valid Admin Passkey required.' : 'Failed to create site'));
  }
  return res.json();
}

export async function deleteSite(siteId: string, adminKey?: string) {
  const res = await fetch(`${API_URL}/sites/${siteId}`, {
    method: 'DELETE',
    headers: getAuthHeaders(adminKey),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || (res.status === 401 ? 'Unauthorized: Valid Admin Passkey required.' : 'Failed to delete site'));
  }
  return res.json();
}

export async function rebootSite(siteId: string, adminKey?: string) {
  const res = await fetch(`${API_URL}/sites/${siteId}/reboot`, {
    method: 'POST',
    headers: getAuthHeaders(adminKey),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || (res.status === 401 ? 'Unauthorized: Valid Admin Passkey required.' : 'Failed to reboot site'));
  }
  return res.json();
}

export async function backupSite(siteId: string, adminKey?: string) {
  const res = await fetch(`${API_URL}/sites/${siteId}/backup`, {
    method: 'POST',
    headers: getAuthHeaders(adminKey),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || (res.status === 401 ? 'Unauthorized: Valid Admin Passkey required.' : 'Failed to backup site'));
  }
  return res.json();
}

export async function updateSite(siteId: string, adminKey?: string) {
  const res = await fetch(`${API_URL}/sites/${siteId}/update`, {
    method: 'POST',
    headers: getAuthHeaders(adminKey),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || (res.status === 401 ? 'Unauthorized: Valid Admin Passkey required.' : 'Failed to run updates'));
  }
  return res.json();
}
