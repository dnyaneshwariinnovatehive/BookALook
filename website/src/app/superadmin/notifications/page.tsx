'use client';

import { useState, useEffect, useMemo } from 'react';
import { useConfirm } from '@/components/admin/ui';
import styles from './notifications.module.css';

interface NotificationTemplate {
  id: string;
  key: string;
  type: string;
  audience: 'customer' | 'partner';
  is_enabled: boolean;
  default_title: string;
  default_message: string;
  title: string | null;
  message: string | null;
  available_variables: string[] | null;
  channels: string[] | null;
  active_title?: string;
  active_message?: string;
}

export default function NotificationsPage() {
  const [templates, setTemplates] = useState<NotificationTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [audienceFilter, setAudienceFilter] = useState<'all' | 'customer' | 'partner'>('all');
  
  const [editingTemplate, setEditingTemplate] = useState<NotificationTemplate | null>(null);
  const [editForm, setEditForm] = useState({
    title: '',
    message: '',
    is_enabled: true
  });
  const [saving, setSaving] = useState(false);

  const confirm = useConfirm();

  const fetchTemplates = async () => {
    try {
      const res = await fetch('/api/superadmin/notification-templates');
      if (!res.ok) throw new Error('Failed to load templates');
      const data = await res.json();
      setTemplates(data);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchTemplates();
  }, []);

  const filteredTemplates = useMemo(() => {
    return templates.filter(t => {
      if (audienceFilter !== 'all' && t.audience !== audienceFilter) return false;
      if (search) {
        const query = search.toLowerCase();
        return (
          t.key.toLowerCase().includes(query) ||
          t.type.toLowerCase().includes(query) ||
          (t.title || t.default_title).toLowerCase().includes(query)
        );
      }
      return true;
    });
  }, [templates, search, audienceFilter]);

  const activeCount = templates.filter(t => t.is_enabled).length;
  const disabledCount = templates.filter(t => !t.is_enabled).length;

  const handleEdit = (template: NotificationTemplate) => {
    setEditingTemplate(template);
    setEditForm({
      title: template.title || template.default_title,
      message: template.message || template.default_message,
      is_enabled: template.is_enabled
    });
  };

  const handleSave = async () => {
    if (!editingTemplate) return;
    setSaving(true);
    try {
      const res = await fetch(`/api/superadmin/notification-templates/${editingTemplate.key}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: editForm.title === editingTemplate.default_title ? null : editForm.title,
          message: editForm.message === editingTemplate.default_message ? null : editForm.message,
          is_enabled: editForm.is_enabled
        })
      });
      if (!res.ok) throw new Error('Failed to update template');
      const data = await res.json();
      setTemplates(templates.map(t => t.key === editingTemplate.key ? data : t));
      setEditingTemplate(null);
    } catch (e) {
      console.error(e);
      alert('Failed to save template');
    } finally {
      setSaving(false);
    }
  };

  const handleReset = async () => {
    if (!editingTemplate) return;
    
    if (await confirm('Reset to default?', 'This will remove your custom wording and restore the default text.')) {
      setSaving(true);
      try {
        const res = await fetch(`/api/superadmin/notification-templates/${editingTemplate.key}/reset`, {
          method: 'POST'
        });
        if (!res.ok) throw new Error('Failed to reset template');
        const data = await res.json();
        setTemplates(templates.map(t => t.key === editingTemplate.key ? data : t));
        setEditingTemplate(null);
      } catch (e) {
        console.error(e);
        alert('Failed to reset template');
      } finally {
        setSaving(false);
      }
    }
  };

  const handleToggleList = async (template: NotificationTemplate) => {
    try {
      const res = await fetch(`/api/superadmin/notification-templates/${template.key}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          is_enabled: !template.is_enabled
        })
      });
      if (!res.ok) throw new Error('Failed to toggle template');
      const data = await res.json();
      setTemplates(templates.map(t => t.key === template.key ? data : t));
    } catch (e) {
      console.error(e);
      alert('Failed to toggle template');
    }
  };

  const insertVariable = (variable: string) => {
    setEditForm(prev => ({
      ...prev,
      message: prev.message + ` {{${variable}}}`
    }));
  };

  // Preview dummy data logic
  const renderPreview = (text: string) => {
    let result = text;
    const dummyData: Record<string, string> = {
      salon_name: 'Glam Studio',
      customer_name: 'Jane Doe',
      owner_name: 'John Smith',
      date_label: '10 Oct 2026 at 5:30 PM',
      advance_due: '₹200.00',
      advance_amount: '₹200.00',
      reason: ' (Provider sick)',
      when: 'in 3 days',
      plan_name: 'Pro Plan',
      live_until_msg: 'It is live until 10 Nov 2026 — no call needed.',
      salon_address: '123 Main St, Tech Park'
    };

    if (editingTemplate?.available_variables) {
      editingTemplate.available_variables.forEach(v => {
        const value = dummyData[v] || `[${v}]`;
        result = result.replace(new RegExp(`\\{\\{${v}\\}\\}`, 'g'), value);
      });
    }

    return result;
  };

  if (loading) return <div>Loading notifications...</div>;

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1>Notification Templates</h1>
      </div>

      <div className={styles.dashboardCards}>
        <div className={styles.card}>
          <div className={styles.cardTitle}>Total Templates</div>
          <div className={styles.cardValue}>{templates.length}</div>
        </div>
        <div className={styles.card}>
          <div className={styles.cardTitle}>Active</div>
          <div className={styles.cardValue} style={{ color: '#16a34a' }}>{activeCount}</div>
        </div>
        <div className={styles.card}>
          <div className={styles.cardTitle}>Disabled</div>
          <div className={styles.cardValue} style={{ color: '#dc2626' }}>{disabledCount}</div>
        </div>
      </div>

      <div className={styles.filters}>
        <input 
          type="text" 
          placeholder="Search notifications..." 
          className={styles.searchInput}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select 
          className={styles.select}
          value={audienceFilter}
          onChange={(e) => setAudienceFilter(e.target.value as any)}
        >
          <option value="all">All Audiences</option>
          <option value="customer">Customer App</option>
          <option value="partner">Partner App</option>
        </select>
      </div>

      <table className={styles.table}>
        <thead>
          <tr>
            <th>Name / Trigger</th>
            <th>Audience</th>
            <th>Channels</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {filteredTemplates.map(t => (
            <tr key={t.id}>
              <td>
                <div style={{ fontWeight: 600, color: '#1e293b', marginBottom: 4 }}>
                  {t.title || t.default_title}
                </div>
                <div style={{ fontSize: 12, color: '#64748b' }}>
                  {t.key}
                </div>
              </td>
              <td>
                <span className={`${styles.audienceBadge} ${t.audience === 'customer' ? styles.audienceCustomer : styles.audiencePartner}`}>
                  {t.audience}
                </span>
              </td>
              <td>
                {t.channels?.map(c => <span key={c} className={styles.channelPill}>{c}</span>)}
              </td>
              <td>
                <label className={styles.toggleSwitch}>
                  <input 
                    type="checkbox" 
                    checked={t.is_enabled}
                    onChange={() => handleToggleList(t)}
                  />
                  <span className={styles.slider}></span>
                </label>
              </td>
              <td>
                <div className={styles.actions}>
                  <button className={styles.editBtn} onClick={() => handleEdit(t)}>Edit</button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {editingTemplate && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <div className={styles.modalHeader}>
              <h2>Edit Notification: {editingTemplate.key}</h2>
              <button className={styles.closeBtn} onClick={() => setEditingTemplate(null)}>&times;</button>
            </div>
            
            <div className={styles.modalBody}>
              <div className={styles.editorSection}>
                <div className={styles.formGroup} style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                  <label>Status</label>
                  <label className={styles.toggleSwitch}>
                    <input 
                      type="checkbox" 
                      checked={editForm.is_enabled}
                      onChange={(e) => setEditForm({...editForm, is_enabled: e.target.checked})}
                    />
                    <span className={styles.slider}></span>
                  </label>
                </div>

                <div className={styles.formGroup}>
                  <label>Notification Title</label>
                  <input 
                    type="text" 
                    className={styles.input}
                    value={editForm.title}
                    onChange={(e) => setEditForm({...editForm, title: e.target.value})}
                  />
                </div>

                <div className={styles.formGroup}>
                  <label>Notification Message</label>
                  <textarea 
                    className={styles.textarea}
                    value={editForm.message}
                    onChange={(e) => setEditForm({...editForm, message: e.target.value})}
                  />
                  
                  {editingTemplate.available_variables && editingTemplate.available_variables.length > 0 && (
                    <div className={styles.variablesBox}>
                      <p>Available Variables (click to insert):</p>
                      <div className={styles.variablesList}>
                        {editingTemplate.available_variables.map(v => (
                          <span 
                            key={v} 
                            className={styles.variablePill}
                            onClick={() => insertVariable(v)}
                          >
                            {`{{${v}}}`}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
                
                <div style={{ fontSize: 13, color: '#64748b', marginTop: 'auto' }}>
                  <strong>Note:</strong> Changes apply to In-App and Push. WhatsApp messages use approved templates and may ignore custom wording.
                </div>
              </div>

              <div className={styles.previewSection}>
                <h3 style={{ margin: '0 0 16px 0', fontSize: 16 }}>Live Preview</h3>
                <div className={styles.phonePreview}>
                  <div className={styles.previewHeader}>Lock Screen</div>
                  <div className={styles.previewNotification}>
                    <div className={styles.previewApp}>
                      <span style={{ fontSize: 16 }}>⌘</span> BookALook {editingTemplate.audience === 'partner' ? 'Partner' : ''}
                    </div>
                    <div className={styles.previewTitle}>
                      {renderPreview(editForm.title)}
                    </div>
                    <div className={styles.previewMessage}>
                      {renderPreview(editForm.message)}
                    </div>
                  </div>
                </div>
              </div>
            </div>
            
            <div className={styles.modalFooter}>
              <button className={styles.resetBtn} onClick={handleReset} disabled={saving}>
                Reset to Default
              </button>
              <div style={{ display: 'flex', gap: 12 }}>
                <button className={styles.resetBtn} style={{ color: '#475569', borderColor: '#cbd5e1' }} onClick={() => setEditingTemplate(null)}>
                  Cancel
                </button>
                <button className={styles.saveBtn} onClick={handleSave} disabled={saving}>
                  {saving ? 'Saving...' : 'Save Changes'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
