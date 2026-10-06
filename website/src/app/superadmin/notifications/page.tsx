'use client';

import { useState, useEffect, useMemo, useRef } from 'react';
import { useConfirm } from '@/components/admin/ui';
import styles from './notifications.module.css';

interface NotificationTemplate {
  id: string;
  key: string;
  type: string;
  audience: 'customer' | 'partner' | 'superadmin';
  name: string | null;
  description: string | null;
  category: string | null;
  is_enabled: boolean;
  default_title: string;
  default_message: string;
  default_push_title: string | null;
  default_push_message: string | null;
  title: string | null;
  message: string | null;
  push_title: string | null;
  push_message: string | null;
  push_image_url: string | null;
  available_variables: string[] | null;
  channels: string[] | null;
  action_config: any | null;
  schedule_config: any | null;
  
  // Accessors appended by backend
  active_title?: string;
  active_message?: string;
  active_push_title?: string;
  active_push_message?: string;
}

export default function NotificationsPage() {
  const [templates, setTemplates] = useState<NotificationTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [audienceFilter, setAudienceFilter] = useState<'all' | 'customer' | 'partner'>('all');
  const [categoryFilter, setCategoryFilter] = useState<string>('all');
  
  const [editingTemplate, setEditingTemplate] = useState<NotificationTemplate | null>(null);
  const [editForm, setEditForm] = useState({
    is_enabled: true,
    in_app_enabled: true,
    push_enabled: true,
    title: '',
    message: '',
    push_title: '',
    push_message: '',
    push_image_url: '',
    action_type: 'default',
    schedule_type: 'immediate',
    schedule_delay_minutes: 0,
  });
  
  const [uploadingImage, setUploadingImage] = useState(false);
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [confirm, confirmDialog] = useConfirm();

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

  const categories = useMemo(() => {
    const cats = new Set<string>();
    templates.forEach(t => {
      if (t.category) cats.add(t.category);
    });
    return Array.from(cats).sort();
  }, [templates]);

  const filteredTemplates = useMemo(() => {
    return templates.filter(t => {
      if (audienceFilter !== 'all' && t.audience !== audienceFilter) return false;
      if (categoryFilter !== 'all' && t.category !== categoryFilter) return false;
      if (search) {
        const query = search.toLowerCase();
        return (
          (t.name || '').toLowerCase().includes(query) ||
          t.key.toLowerCase().includes(query) ||
          (t.title || t.default_title).toLowerCase().includes(query)
        );
      }
      return true;
    });
  }, [templates, search, audienceFilter, categoryFilter]);

  const activeCount = templates.filter(t => t.is_enabled).length;
  const disabledCount = templates.filter(t => !t.is_enabled).length;

  const handleEdit = (template: NotificationTemplate) => {
    setEditingTemplate(template);
    
    // Parse channels safely
    const ch = Array.isArray(template.channels) ? template.channels : [];
    
    setEditForm({
      is_enabled: template.is_enabled,
      in_app_enabled: ch.includes('in_app'),
      push_enabled: ch.includes('push'),
      title: template.title || template.default_title,
      message: template.message || template.default_message,
      push_title: template.push_title || template.default_push_title || template.title || template.default_title,
      push_message: template.push_message || template.default_push_message || template.message || template.default_message,
      push_image_url: template.push_image_url || '',
      action_type: template.action_config?.type || 'default',
      schedule_type: template.schedule_config?.type || 'immediate',
      schedule_delay_minutes: template.schedule_config?.delay_minutes || 0,
    });
  };

  const handleSave = async () => {
    if (!editingTemplate) return;
    setSaving(true);
    try {
      const body: any = {
        is_enabled: editForm.is_enabled,
        title: editForm.title === editingTemplate.default_title ? null : editForm.title,
        message: editForm.message === editingTemplate.default_message ? null : editForm.message,
        push_image_url: editForm.push_image_url || null
      };

      // Only send push overrides if they differ from the default push fallbacks
      const fallbackPushTitle = editingTemplate.default_push_title || editingTemplate.title || editingTemplate.default_title;
      const fallbackPushMessage = editingTemplate.default_push_message || editingTemplate.message || editingTemplate.default_message;
      
      body.push_title = editForm.push_title === fallbackPushTitle ? null : editForm.push_title;
      body.push_message = editForm.push_message === fallbackPushMessage ? null : editForm.push_message;

      if (editForm.action_type !== 'default') {
        body.action_config = { type: editForm.action_type };
      } else {
        body.action_config = null;
      }
      
      if (editForm.schedule_type !== 'immediate') {
        body.schedule_config = { type: editForm.schedule_type, delay_minutes: editForm.schedule_delay_minutes };
      } else {
        body.schedule_config = null;
      }
      
      const newChannels = Array.isArray(editingTemplate.channels) ? [...editingTemplate.channels] : [];
      if (editForm.in_app_enabled && !newChannels.includes('in_app')) newChannels.push('in_app');
      if (!editForm.in_app_enabled) {
        const idx = newChannels.indexOf('in_app');
        if (idx > -1) newChannels.splice(idx, 1);
      }
      
      if (editForm.push_enabled && !newChannels.includes('push')) newChannels.push('push');
      if (!editForm.push_enabled) {
        const idx = newChannels.indexOf('push');
        if (idx > -1) newChannels.splice(idx, 1);
      }
      
      body.channels = newChannels;

      const res = await fetch(`/api/superadmin/notification-templates/${editingTemplate.key}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
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

  const handleTest = async () => {
    if (!editingTemplate) return;
    setTesting(true);
    try {
      const body: any = {
        title: editForm.title,
        message: editForm.message,
        push_title: editForm.push_title,
        push_message: editForm.push_message,
        push_image_url: editForm.push_image_url || null
      };

      if (editForm.action_type !== 'default') {
        body.action_config = { type: editForm.action_type };
      }

      const res = await fetch(`/api/superadmin/notification-templates/${editingTemplate.key}/test`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      if (!res.ok) throw new Error('Failed to send test notification');
      alert('Test notification sent successfully to your account!');
    } catch (e) {
      console.error(e);
      alert('Failed to send test notification');
    } finally {
      setTesting(false);
    }
  };

  const handleReset = async () => {
    if (!editingTemplate) return;
    
    if (await confirm({ title: 'Reset to default?', body: 'This will remove your custom wording and restore the BookALook defaults.', confirmLabel: 'Reset', tone: 'danger' })) {
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

  const insertVariable = (field: 'message' | 'title' | 'push_title' | 'push_message', variable: string) => {
    setEditForm(prev => ({
      ...prev,
      [field]: prev[field] + ` {{${variable}}}`
    }));
  };

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const formData = new FormData();
    formData.append('image', file);

    setUploadingImage(true);
    try {
      const res = await fetch('/api/superadmin/notification-templates/upload-image', {
        method: 'POST',
        body: formData
      });
      if (!res.ok) throw new Error('Upload failed');
      const data = await res.json();
      setEditForm(prev => ({ ...prev, push_image_url: data.url }));
    } catch (e) {
      console.error(e);
      alert('Failed to upload image');
    } finally {
      setUploadingImage(false);
    }
  };

  // Preview dummy data logic
  const renderPreview = (text: string) => {
    let result = text;
    const dummyData: Record<string, string> = {
      salon_name: 'Glam Studio',
      customer_name: 'Jane Doe',
      owner_name: 'John Smith',
      date_label: 'Tomorrow at 5:30 PM',
      advance_due: '₹200.00',
      advance_amount: '₹200.00',
      reason: ' (Provider sick)',
      when: 'in 3 days',
      plan_name: 'Pro Plan',
      live_until_msg: 'It is live until 10 Nov 2026 — no call needed.',
      salon_address: '123 Main St, Tech Park',
      days_left: '3',
      s: 's',
      days_down: '5 days',
      admin_message: 'Please update your salon policy.'
    };

    if (editingTemplate?.available_variables) {
      editingTemplate.available_variables.forEach(v => {
        const value = dummyData[v] || `[${v}]`;
        result = result.replace(new RegExp(`\\{\\{${v}\\}\\}`, 'g'), value);
      });
    }

    return result;
  };

  if (loading) return <div className={styles.container}>Loading notifications...</div>;

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
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
        >
          <option value="all">All Categories</option>
          {categories.map(c => <option key={c} value={c}>{c}</option>)}
        </select>
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
                <div style={{ fontWeight: 600, color: '#1e293b', marginBottom: 4, fontSize: 15 }}>
                  {t.name || t.title || t.default_title}
                </div>
                <div style={{ fontSize: 12, color: '#64748b' }}>
                  {t.description || t.key}
                </div>
                {t.category && <span className={styles.categoryPill}>{t.category}</span>}
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
                <button className={styles.editBtn} onClick={() => handleEdit(t)}>Edit</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {/* Editor Drawer */}
      {editingTemplate && (
        <div className={styles.drawerOverlay}>
          <div className={styles.drawerContent}>
            <div className={styles.drawerHeader}>
              <div>
                <h2>{editingTemplate.name || editingTemplate.active_title}</h2>
                <p>{editingTemplate.audience.charAt(0).toUpperCase() + editingTemplate.audience.slice(1)} notification • {editingTemplate.description}</p>
              </div>
              <button className={styles.closeBtn} onClick={() => setEditingTemplate(null)}>&times;</button>
            </div>
            
            <div className={styles.drawerBody}>
              
              <div className={styles.editorSection}>
                {/* General */}
                <div className={styles.sectionBox} style={{ borderLeft: '4px solid #10b981' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div>
                      <h3 style={{ marginBottom: 4 }}>Notification Status</h3>
                      <p style={{ margin: 0, fontSize: 13, color: '#64748b' }}>Turn this automatic notification on or off.</p>
                    </div>
                    <label className={styles.toggleSwitch}>
                      <input 
                        type="checkbox" 
                        checked={editForm.is_enabled}
                        onChange={(e) => setEditForm({...editForm, is_enabled: e.target.checked})}
                      />
                      <span className={styles.slider}></span>
                    </label>
                  </div>
                </div>

                {/* In-App Content */}
                <div className={styles.sectionBox}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                    <h3 style={{ margin: 0 }}>IN-APP NOTIFICATION</h3>
                    <label className={styles.toggleSwitch}>
                      <input 
                        type="checkbox" 
                        checked={editForm.in_app_enabled}
                        onChange={(e) => setEditForm({...editForm, in_app_enabled: e.target.checked})}
                      />
                      <span className={styles.slider}></span>
                    </label>
                  </div>
                  
                  {editForm.in_app_enabled && (
                    <>
                      <div className={styles.formGroup}>
                    <label>Title</label>
                    <input 
                      type="text" 
                      className={styles.input}
                      value={editForm.title}
                      onChange={(e) => setEditForm({...editForm, title: e.target.value})}
                    />
                  </div>
                  <div className={styles.formGroup}>
                    <label>Message</label>
                    <textarea 
                      className={styles.textarea}
                      value={editForm.message}
                      onChange={(e) => setEditForm({...editForm, message: e.target.value})}
                    />
                  </div>
                  {editingTemplate.available_variables && editingTemplate.available_variables.length > 0 && (
                    <div className={styles.variablesBox} style={{ marginTop: 12 }}>
                      <p>Personalize your message (click to insert into message):</p>
                      <div className={styles.variablesList}>
                        {editingTemplate.available_variables.map(v => (
                          <span 
                            key={v} 
                            className={styles.variablePill}
                            onClick={() => insertVariable('message', v)}
                          >
                            + {v.replace(/_/g, ' ')}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                    </>
                  )}
                </div>

                {/* Push Content */}
                <div className={styles.sectionBox}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                    <h3 style={{ margin: 0 }}>PUSH NOTIFICATION</h3>
                    <label className={styles.toggleSwitch}>
                      <input 
                        type="checkbox" 
                        checked={editForm.push_enabled}
                        onChange={(e) => setEditForm({...editForm, push_enabled: e.target.checked})}
                      />
                      <span className={styles.slider}></span>
                    </label>
                  </div>
                  
                  {editForm.push_enabled && (
                    <>
                      <div className={styles.formGroup}>
                    <label>Push Title</label>
                    <input 
                      type="text" 
                      className={styles.input}
                      value={editForm.push_title}
                      onChange={(e) => setEditForm({...editForm, push_title: e.target.value})}
                    />
                  </div>
                  <div className={styles.formGroup}>
                    <label>Push Message</label>
                    <textarea 
                      className={styles.textarea}
                      style={{ minHeight: 60 }}
                      value={editForm.push_message}
                      onChange={(e) => setEditForm({...editForm, push_message: e.target.value})}
                    />
                  </div>
                  {editingTemplate.available_variables && editingTemplate.available_variables.length > 0 && (
                    <div className={styles.variablesBox} style={{ marginTop: 12 }}>
                      <p>Personalize your push message (click to insert):</p>
                      <div className={styles.variablesList}>
                        {editingTemplate.available_variables.map(v => (
                          <span 
                            key={v} 
                            className={styles.variablePill}
                            onClick={() => insertVariable('push_message', v)}
                          >
                            + {v.replace(/_/g, ' ')}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}

                  <div className={styles.formGroup} style={{ marginTop: 24 }}>
                    <label>Notification Image (Optional)</label>
                    {editForm.push_image_url ? (
                      <div className={styles.currentImageContainer}>
                        <img src={editForm.push_image_url} alt="Push graphic" />
                        <button className={styles.removeImageBtn} onClick={() => setEditForm({...editForm, push_image_url: ''})}>Remove</button>
                      </div>
                    ) : (
                      <div className={styles.imageUploadBox}>
                        <p>Upload a promotional graphic for this notification.</p>
                        <input 
                          type="file" 
                          accept="image/*" 
                          ref={fileInputRef} 
                          style={{ display: 'none' }} 
                          onChange={handleImageUpload}
                        />
                        <button 
                          className={styles.editBtn} 
                          onClick={() => fileInputRef.current?.click()}
                          disabled={uploadingImage}
                        >
                          {uploadingImage ? 'Uploading...' : 'Upload Image'}
                        </button>
                      </div>
                    )}
                  </div>
                </>
              )}
            </div>

                {/* Action */}
                <div className={styles.sectionBox}>
                  <h3>WHEN THE USER TAPS THIS NOTIFICATION</h3>
                  <div className={styles.formGroup}>
                    <label>Open:</label>
                    <select 
                      className={styles.select}
                      value={editForm.action_type}
                      onChange={(e) => setEditForm({...editForm, action_type: e.target.value})}
                    >
                      <option value="default">Default Behavior</option>
                      <option value="none">No Action (Open App Home)</option>
                      <option value="appointment_details">Appointment Details</option>
                      <option value="salon_profile">Salon Profile</option>
                    </select>
                  </div>
                </div>

                {/* Schedule */}
                <div className={styles.sectionBox}>
                  <h3>SCHEDULE</h3>
                  <div className={styles.formGroup}>
                    <label>When should this be sent?</label>
                    <select 
                      className={styles.select}
                      value={editForm.schedule_type}
                      onChange={(e) => setEditForm({...editForm, schedule_type: e.target.value})}
                    >
                      <option value="immediate">Immediately</option>
                      <option value="delayed">Delayed</option>
                    </select>
                  </div>
                  
                  {editForm.schedule_type === 'delayed' && (
                    <div className={styles.formGroup}>
                      <label>Delay (in minutes)</label>
                      <input 
                        type="number" 
                        className={styles.input}
                        value={editForm.schedule_delay_minutes}
                        onChange={(e) => setEditForm({...editForm, schedule_delay_minutes: parseInt(e.target.value) || 0})}
                      />
                    </div>
                  )}
                </div>

                {/* WhatsApp Note */}
                {editingTemplate.channels?.includes('whatsapp') && (
                  <div className={styles.sectionBox} style={{ borderLeft: '4px solid #128c7e', background: '#f0fdf4' }}>
                    <h3 style={{ color: '#128c7e' }}>WhatsApp Template</h3>
                    <p style={{ margin: 0, fontSize: 13, color: '#334155' }}>
                      This event also triggers a WhatsApp message. WhatsApp messages require Meta approval and are managed in a separate system. Changes made here will only affect In-App and Push.
                    </p>
                  </div>
                )}
              </div>

              {/* Preview Side */}
              <div className={styles.previewSection}>
                <div className={styles.sectionBox} style={{ padding: 16, background: 'transparent', border: 'none' }}>
                  <h3 style={{ marginBottom: 16 }}>Live Preview</h3>
                  
                  {/* Phone Preview */}
                  <div className={styles.phonePreview}>
                    <div className={styles.previewHeader}>Lock Screen</div>
                    <div className={styles.previewNotification}>
                      <div className={styles.previewApp}>
                        <span style={{ fontSize: 16 }}>⌘</span> BookALook {editingTemplate.audience === 'partner' ? 'Partner' : ''}
                      </div>
                      <div className={styles.previewTitle}>
                        {renderPreview(editForm.push_title)}
                      </div>
                      <div className={styles.previewMessage}>
                        {renderPreview(editForm.push_message)}
                      </div>
                      {editForm.push_image_url && (
                        <img src={editForm.push_image_url} className={styles.previewImage} alt="Push" />
                      )}
                    </div>
                  </div>

                  {/* In-App Preview */}
                  <div style={{ marginTop: 24 }}>
                    <div className={styles.previewHeader} style={{ textAlign: 'left', marginBottom: 12 }}>In-App Notification Center</div>
                    <div className={styles.previewInApp}>
                      <div className={styles.previewTitle}>
                        {renderPreview(editForm.title)}
                      </div>
                      <div className={styles.previewMessage}>
                        {renderPreview(editForm.message)}
                      </div>
                      <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 8, textAlign: 'right' }}>2m ago</div>
                    </div>
                  </div>

                </div>
              </div>

            </div>
            
            <div className={styles.drawerFooter}>
              <div style={{ display: 'flex', gap: 12 }}>
                <button className={styles.resetBtn} onClick={handleReset} disabled={saving}>
                  Reset to Default
                </button>
                <button className={styles.testBtn} onClick={handleTest} disabled={testing || saving}>
                  {testing ? 'Sending...' : 'Send Test'}
                </button>
              </div>
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
      
      {confirmDialog}
    </div>
  );
}
