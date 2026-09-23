"use client";

import { use, useState } from 'react';
import useSWR from 'swr';
import { getSite, rebootSite, backupSite, updateSite } from '@/lib/api';
import Link from 'next/link';

export default function SiteDetail({ params }: { params: Promise<{ site_id: string }> }) {
  const unwrappedParams = use(params);
  const siteId = unwrappedParams.site_id;
  const { data: site, error, mutate } = useSWR(`/sites/${siteId}`, () => getSite(siteId), { refreshInterval: 10000 });
  
  const [isRebooting, setIsRebooting] = useState(false);
  const [isBackingUp, setIsBackingUp] = useState(false);
  const [isUpdating, setIsUpdating] = useState(false);

  if (error) return (
    <div className="min-h-screen p-8 md:p-16 lg:p-24 flex items-center justify-center font-mono text-xs tracking-widest uppercase text-red-500">
      ERR: Could_not_load_telemetry
    </div>
  );

  if (!site) return (
    <div className="min-h-screen p-8 md:p-16 lg:p-24 flex items-center justify-center font-mono text-xs tracking-widest uppercase text-zinc-600 animate-pulse">
      Establishing_link...
    </div>
  );

  const metrics = site.health_metrics;

  const handleReboot = async () => {
    if (!confirm('INITIATE REBOOT SEQUENCE? [Y/N]')) return;
    setIsRebooting(true);
    try {
      await rebootSite(siteId);
      alert('REBOOT_SEQ_ACKNOWLEDGED');
    } catch (err) {
      alert('REBOOT_SEQ_FAILED');
    } finally {
      setIsRebooting(false);
    }
  };

  const handleBackup = async () => {
    setIsBackingUp(true);
    try {
      await backupSite(siteId);
      alert('BACKUP_COMPLETE');
    } catch (err) {
      alert('BACKUP_FAILED');
    } finally {
      setIsBackingUp(false);
    }
  };

  const handleUpdate = async () => {
    if (!confirm('INITIATE AUTOMATED MAINTENANCE ROUTINE? (Pre-update snapshot will be created automatically) [Y/N]')) return;
    setIsUpdating(true);
    try {
      const res = await updateSite(siteId);
      alert('UPDATE_ROUTINE_COMPLETE:\n' + (res.message || 'Updated successfully'));
      mutate();
    } catch (err: any) {
      alert('UPDATE_FAILED: ' + err.message);
    } finally {
      setIsUpdating(false);
    }
  };

  return (
    <div className="min-h-screen p-8 md:p-16 lg:p-24 flex flex-col font-light">
      <header className="mb-16 flex flex-col md:flex-row md:justify-between md:items-end border-b border-zinc-800 pb-6 gap-6">
        <div>
          <Link href="/" className="text-[10px] font-mono tracking-widest uppercase text-zinc-600 hover:text-zinc-300 transition-colors mb-6 block">
            &larr; Return_to_base
          </Link>
          <h1 className="text-xl tracking-widest uppercase font-mono text-zinc-100">{site.site_id}</h1>
          <div className="flex flex-col gap-1 mt-3">
            {site.public_url && (
              <div className="flex items-center gap-2">
                <span className="text-[10px] font-mono tracking-widest uppercase text-zinc-600">Live Endpoint:</span>
                <a href={site.public_url} target="_blank" rel="noreferrer" className="text-xs font-mono text-emerald-400 hover:text-emerald-300 transition-colors">
                  {site.alb_dns_name} &rarr;
                </a>
              </div>
            )}
            <div className="flex items-center gap-3">
              <span className="text-[10px] font-mono tracking-widest uppercase text-zinc-600">Domain:</span>
              <span className="text-xs font-mono text-zinc-400">{site.domain || 'None'}</span>
              <span className="text-[10px] font-mono tracking-widest uppercase text-zinc-500">
                [{site.status}]
              </span>
            </div>
          </div>
        </div>
        
        <div className="flex flex-wrap gap-4">
          <button 
            onClick={handleUpdate}
            disabled={isUpdating || site.status !== 'AVAILABLE'}
            className="text-[10px] font-mono tracking-widest uppercase border border-emerald-900 bg-emerald-950/30 text-emerald-400 px-4 py-2 hover:bg-emerald-900 hover:text-white transition-colors disabled:opacity-30"
          >
            {isUpdating ? 'Updating...' : 'Apply_Updates'}
          </button>
          <button 
            onClick={handleBackup}
            disabled={isBackingUp || site.status !== 'AVAILABLE'}
            className="text-[10px] font-mono tracking-widest uppercase border border-zinc-800 px-4 py-2 hover:bg-zinc-800 hover:text-white transition-colors disabled:opacity-30"
          >
            {isBackingUp ? 'Processing...' : 'Run_Backup'}
          </button>
          <button 
            onClick={handleReboot}
            disabled={isRebooting || site.status !== 'AVAILABLE'}
            className="text-[10px] font-mono tracking-widest uppercase border border-zinc-800 px-4 py-2 hover:bg-red-950 hover:text-red-400 hover:border-red-900 transition-colors disabled:opacity-30"
          >
            {isRebooting ? 'Rebooting...' : 'Restart_Instance'}
          </button>
        </div>
      </header>

      <main className="flex-1">
        
        {site.status === 'PROVISIONING' && (
          <div className="border border-yellow-900/50 bg-yellow-950/20 p-6 mb-12">
            <p className="text-xs font-mono tracking-widest uppercase text-yellow-500/70">
              &gt; Instance is currently provisioning. Telemetry offline.
            </p>
          </div>
        )}

        <h2 className="text-[10px] font-mono tracking-widest uppercase text-zinc-600 mb-8 border-b border-zinc-900 pb-2">
          Telemetry_Data
        </h2>
        
        {!metrics && site.status === 'AVAILABLE' && (
          <div className="text-xs font-mono tracking-widest uppercase text-zinc-600 animate-pulse">
            Awaiting_first_telemetry_ping...
          </div>
        )}

        {metrics && (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-px bg-zinc-800 border border-zinc-800">
            
            {/* Disk Usage */}
            <div className="bg-[#0a0a0a] p-8 flex flex-col justify-between min-h-[160px]">
              <h3 className="text-[10px] font-mono tracking-widest uppercase text-zinc-600">Storage_IO</h3>
              <div className="text-2xl font-mono text-zinc-200">{metrics.disk_usage || 'UNKNOWN'}</div>
            </div>

            {/* Core Updates */}
            <div className="bg-[#0a0a0a] p-8 flex flex-col justify-between min-h-[160px]">
              <h3 className="text-[10px] font-mono tracking-widest uppercase text-zinc-600">Core_Version</h3>
              <div>
                <div className="text-2xl font-mono text-zinc-200">{metrics.core_updates ?? '-'}</div>
                <div className="text-[10px] font-mono tracking-widest uppercase mt-2">
                  {metrics.core_updates === 0 ? <span className="text-emerald-500/70">Up_to_date</span> : <span className="text-yellow-500/70">Updates_avail</span>}
                </div>
              </div>
            </div>

            {/* Plugin Updates */}
            <div className="bg-[#0a0a0a] p-8 flex flex-col justify-between min-h-[160px]">
              <h3 className="text-[10px] font-mono tracking-widest uppercase text-zinc-600">Module_Updates</h3>
              <div>
                <div className="text-2xl font-mono text-zinc-200">{metrics.plugin_updates ?? '-'}</div>
                <div className="text-[10px] font-mono tracking-widest uppercase mt-2">
                  {metrics.plugin_updates === 0 ? <span className="text-emerald-500/70">Up_to_date</span> : <span className="text-yellow-500/70">Updates_avail</span>}
                </div>
              </div>
            </div>

            {/* SSL Expiry */}
            <div className="bg-[#0a0a0a] p-8 flex flex-col justify-between min-h-[160px]">
              <h3 className="text-[10px] font-mono tracking-widest uppercase text-zinc-600">Cert_Validity</h3>
              <div className="text-2xl font-mono text-zinc-200">
                {metrics.ssl_days_remaining === -1 ? 'ACM_MNGD' : metrics.ssl_days_remaining}
              </div>
            </div>

          </div>
        )}

      </main>
    </div>
  );
}
