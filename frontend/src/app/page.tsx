"use client";

import { useState, useEffect } from 'react';
import useSWR from 'swr';
import { getSites, createSite, deleteSite, getAdminKey, setAdminKey } from '@/lib/api';
import Link from 'next/link';

export default function Dashboard() {
  const { data: sites, error, isLoading, mutate } = useSWR('/sites', getSites, { refreshInterval: 10000 });
  
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [newSiteId, setNewSiteId] = useState('');
  const [newDomain, setNewDomain] = useState('');
  const [adminPasskey, setAdminPasskey] = useState('');
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState('');

  useEffect(() => {
    setAdminPasskey(getAdminKey());
  }, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsCreating(true);
    setCreateError('');
    try {
      setAdminKey(adminPasskey);
      await createSite(newSiteId, newDomain, 't3.micro', adminPasskey);
      setIsModalOpen(false);
      setNewSiteId('');
      setNewDomain('');
      mutate();
    } catch (err: any) {
      setCreateError(err.message);
    } finally {
      setIsCreating(false);
    }
  };

  const handleDelete = async (siteId: string) => {
    if (!confirm(`Are you sure you want to delete ${siteId}?`)) return;
    let key = adminPasskey || getAdminKey();
    if (!key) {
      const entered = prompt('ENTER ADMIN PASSKEY TO AUTHORIZE DELETION:');
      if (!entered) return;
      key = entered;
      setAdminPasskey(key);
      setAdminKey(key);
    }
    try {
      await deleteSite(siteId, key);
      mutate();
    } catch (err: any) {
      alert('Delete failed: ' + err.message);
    }
  };

  const handleToggleAuth = () => {
    const nextKey = prompt('Update Admin Passkey (leave blank to lock/clear):', adminPasskey);
    if (nextKey !== null) {
      setAdminPasskey(nextKey.trim());
      setAdminKey(nextKey.trim());
    }
  };

  const getStatusDot = (status: string) => {
    switch (status) {
      case 'AVAILABLE': return <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></span>;
      case 'PROVISIONING': return <span className="w-1.5 h-1.5 rounded-full bg-yellow-500 animate-ping"></span>;
      case 'DESTROYING': return <span className="w-1.5 h-1.5 rounded-full bg-orange-500 animate-ping"></span>;
      case 'FAILED': return <span className="w-1.5 h-1.5 rounded-full bg-red-500"></span>;
      default: return <span className="w-1.5 h-1.5 rounded-full bg-zinc-600"></span>;
    }
  };

  return (
    <div className="min-h-screen p-8 md:p-16 lg:p-24 flex flex-col font-light">
      <header className="mb-16 flex justify-between items-end border-b border-zinc-800 pb-6">
        <div>
          <h1 className="text-xl tracking-widest uppercase font-mono text-zinc-100">CloudPress</h1>
          <p className="text-xs tracking-widest uppercase font-mono text-zinc-600 mt-2">Control Center</p>
        </div>
        <div className="flex items-center gap-3">
          <button 
            onClick={handleToggleAuth}
            title="Click to set or clear Admin Passkey"
            className="text-[10px] font-mono tracking-widest uppercase border border-zinc-800 px-3 py-2 text-zinc-400 hover:text-zinc-100 hover:border-zinc-700 transition-colors"
          >
            {adminPasskey ? '[AUTH: ADMIN]' : '[AUTH: LOCKED]'}
          </button>
          <button 
            onClick={() => setIsModalOpen(true)}
            className="text-xs font-mono tracking-widest uppercase border border-zinc-800 px-4 py-2 hover:bg-zinc-800 hover:text-white transition-colors rounded-sm"
          >
            [+ Deploy Site]
          </button>
        </div>
      </header>

      <main className="flex-1">
        {isLoading && (
          <div className="text-zinc-600 font-mono text-xs tracking-widest uppercase animate-pulse">
            Loading_sites...
          </div>
        )}
        
        {error && (
          <div className="text-red-500 font-mono text-xs tracking-widest uppercase">
            ERR: Failed to load payload.
          </div>
        )}

        {!isLoading && !error && sites?.length === 0 && (
          <div className="text-zinc-600 font-mono text-xs tracking-widest uppercase">
            No_deployments_found.
          </div>
        )}

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
          {sites?.map((site) => (
            <div key={site.site_id} className="border border-zinc-800 p-6 flex flex-col hover:border-zinc-700 transition-colors group relative">
              <div className="flex justify-between items-start mb-8">
                <h3 className="text-lg font-medium tracking-wide text-zinc-200 group-hover:text-white transition-colors truncate">
                  {site.site_id}
                </h3>
                <div className="flex items-center gap-2">
                  {getStatusDot(site.status)}
                  <span className="text-[10px] font-mono tracking-widest uppercase text-zinc-500">
                    {site.status}
                  </span>
                </div>
              </div>
              
              <div className="space-y-4 mb-12">
                <div className="flex flex-col">
                  <span className="text-[10px] font-mono tracking-widest uppercase text-zinc-600 mb-1">Live Endpoint (ALB)</span>
                  {site.public_url ? (
                    <a href={site.public_url} target="_blank" rel="noreferrer" className="text-xs text-emerald-400 hover:text-emerald-300 font-mono transition-colors truncate">
                      {site.alb_dns_name}
                    </a>
                  ) : (
                    <span className="text-xs text-zinc-600 font-mono">Provisioning...</span>
                  )}
                </div>
                <div className="flex flex-col">
                  <span className="text-[10px] font-mono tracking-widest uppercase text-zinc-600 mb-1">Domain</span>
                  {site.domain ? (
                    <span className="text-sm text-zinc-300 font-mono truncate">{site.domain}</span>
                  ) : (
                    <span className="text-sm text-zinc-600 font-mono">None</span>
                  )}
                </div>
                <div className="flex flex-col">
                  <span className="text-[10px] font-mono tracking-widest uppercase text-zinc-600 mb-1">Compute</span>
                  <span className="text-sm text-zinc-400 font-mono">{site.instance_size || 't3.micro'}</span>
                </div>
              </div>
              
              <div className="mt-auto flex justify-between items-center border-t border-zinc-900 pt-4">
                <Link href={`/sites/${site.site_id}`} className="text-xs font-mono tracking-widest uppercase text-zinc-500 hover:text-zinc-300 transition-colors">
                  View_metrics &rarr;
                </Link>
                <button 
                  onClick={() => handleDelete(site.site_id)}
                  className="text-xs font-mono tracking-widest uppercase text-zinc-700 hover:text-red-500 transition-colors"
                >
                  [DEL]
                </button>
              </div>
            </div>
          ))}
        </div>
      </main>

      {/* Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-[#0a0a0a]/80 backdrop-blur-sm">
          <div className="bg-[#0a0a0a] border border-zinc-800 p-8 w-full max-w-md">
            <h3 className="text-sm font-mono tracking-widest uppercase text-zinc-100 mb-8 border-b border-zinc-800 pb-4">
              Initialize_deployment
            </h3>
            
            <form onSubmit={handleCreate} className="space-y-6">
              {createError && (
                <div className="text-xs font-mono tracking-widest text-red-500 uppercase">
                  ERR: {createError}
                </div>
              )}

              <div className="space-y-4">
                <div>
                  <label className="block text-[10px] font-mono tracking-widest uppercase text-zinc-500 mb-2">Site_ID</label>
                  <input 
                    type="text" 
                    required 
                    pattern="[a-zA-Z0-9-]+"
                    className="w-full bg-transparent border-b border-zinc-800 px-0 py-2 text-zinc-200 text-sm font-mono focus:outline-none focus:border-zinc-500 transition-colors" 
                    placeholder="site-alpha"
                    value={newSiteId}
                    onChange={(e) => setNewSiteId(e.target.value)}
                  />
                </div>
                <div>
                  <label className="block text-[10px] font-mono tracking-widest uppercase text-zinc-500 mb-2">Domain</label>
                  <input 
                    type="text" 
                    required 
                    className="w-full bg-transparent border-b border-zinc-800 px-0 py-2 text-zinc-200 text-sm font-mono focus:outline-none focus:border-zinc-500 transition-colors" 
                    placeholder="example.com"
                    value={newDomain}
                    onChange={(e) => setNewDomain(e.target.value)}
                  />
                </div>
                <div>
                  <div className="flex justify-between items-center mb-2">
                    <label className="text-[10px] font-mono tracking-widest uppercase text-zinc-500">Admin_Passkey</label>
                    <span className="text-[9px] font-mono text-zinc-600">Required for AWS deployment</span>
                  </div>
                  <input 
                    type="password" 
                    required 
                    className="w-full bg-transparent border-b border-zinc-800 px-0 py-2 text-zinc-200 text-sm font-mono focus:outline-none focus:border-zinc-500 transition-colors" 
                    placeholder="••••••••••••"
                    value={adminPasskey}
                    onChange={(e) => setAdminPasskey(e.target.value)}
                  />
                </div>
              </div>

              <div className="flex gap-4 pt-4">
                <button 
                  type="submit" 
                  disabled={isCreating}
                  className="flex-1 text-xs font-mono tracking-widest uppercase bg-zinc-100 text-[#0a0a0a] py-3 hover:bg-white transition-colors disabled:opacity-50"
                >
                  {isCreating ? 'Deploying...' : 'Execute'}
                </button>
                <button 
                  type="button" 
                  onClick={() => setIsModalOpen(false)}
                  className="flex-1 text-xs font-mono tracking-widest uppercase border border-zinc-800 text-zinc-400 hover:text-zinc-100 transition-colors"
                >
                  Abort
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
