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
  created_at?: number;
  health_metrics?: HealthMetrics;
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

export async function createSite(siteId: string, domain: string, instanceSize: string = 't3.micro') {
  const res = await fetch(`${API_URL}/sites`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ site_id: siteId, domain, instance_size: instanceSize }),
  });
  if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Failed to create site');
  }
  return res.json();
}

export async function deleteSite(siteId: string) {
  const res = await fetch(`${API_URL}/sites/${siteId}`, { method: 'DELETE' });
  if (!res.ok) throw new Error('Failed to delete site');
  return res.json();
}

export async function rebootSite(siteId: string) {
  const res = await fetch(`${API_URL}/sites/${siteId}/reboot`, { method: 'POST' });
  if (!res.ok) throw new Error('Failed to reboot site');
  return res.json();
}

export async function backupSite(siteId: string) {
  const res = await fetch(`${API_URL}/sites/${siteId}/backup`, { method: 'POST' });
  if (!res.ok) throw new Error('Failed to backup site');
  return res.json();
}
